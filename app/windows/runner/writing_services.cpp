#include "writing_services.h"
#include <windows.h>
#include <spellcheck.h>
// Select standard coroutines before C++/WinRT checks the library feature macro.
#include <coroutine>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Input.Inking.h>
#include <algorithm>
#include <cmath>
#include <cwctype>
#include <map>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
using L = flutter::EncodableList;
const V& Field(const M& m, const char* key) { return m.at(V(key)); }
double Number(const V& v) {
  if (const auto p = std::get_if<double>(&v)) return *p;
  if (const auto p = std::get_if<int32_t>(&v)) return *p;
  if (const auto p = std::get_if<int64_t>(&v)) return static_cast<double>(*p);
  throw std::invalid_argument("Invalid point");
}
winrt::com_ptr<ISpellChecker> Checker(const std::string& lang) {
  auto factory = winrt::create_instance<ISpellCheckerFactory>(
      __uuidof(SpellCheckerFactory), CLSCTX_INPROC_SERVER);
  winrt::com_ptr<ISpellChecker> checker;
  winrt::check_hresult(factory->CreateSpellChecker(
      winrt::to_hstring(lang).c_str(), checker.put()));
  return checker;
}
L Check(ISpellChecker* checker, const std::string& text) {
  winrt::com_ptr<IEnumSpellingError> errors;
  winrt::check_hresult(checker->Check(winrt::to_hstring(text).c_str(), errors.put()));
  L result;
  for (;;) {
    winrt::com_ptr<ISpellingError> error;
    const auto hr = errors->Next(error.put());
    if (hr == S_FALSE || !error) break;
    winrt::check_hresult(hr);
    ULONG start = 0, length = 0;
    CORRECTIVE_ACTION action = CORRECTIVE_ACTION_NONE;
    winrt::check_hresult(error->get_StartIndex(&start));
    winrt::check_hresult(error->get_Length(&length));
    winrt::check_hresult(error->get_CorrectiveAction(&action));
    if (action != CORRECTIVE_ACTION_NONE) result.emplace_back(M{
      {V("start"), V(static_cast<int64_t>(start))},
      {V("length"), V(static_cast<int64_t>(length))}});
  }
  return result;
}
V Run(const M& args) {
  using namespace winrt::Windows::UI::Input::Inking;
  const auto lang = std::get<std::string>(Field(args, "language"));
  if (lang != "de-DE" && lang != "en-US") throw std::invalid_argument("Unsupported language");
  const auto kind = std::get<std::string>(Field(args, "kind"));
  auto checker = Checker(lang);
  if (kind == "text") {
    const auto text = std::get<std::string>(Field(args, "text"));
    if (text.size() > 2000000) throw std::invalid_argument("Text is too long");
    return V(Check(checker.get(), text));
  }
  InkRecognizerContainer recognizers;
  bool available = false;
  L names;
  for (const auto& recognizer : recognizers.GetRecognizers()) {
    names.emplace_back(winrt::to_string(recognizer.Name()));
    std::wstring name(recognizer.Name().c_str());
    std::transform(name.begin(), name.end(), name.begin(),
        [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
    const bool match = lang == "de-DE"
        ? (name.find(L"german") != std::wstring::npos || name.find(L"deutsch") != std::wstring::npos)
        : (name.find(L"english") != std::wstring::npos || name.find(L"englisch") != std::wstring::npos);
    if (match && !available) { recognizers.SetDefaultRecognizer(recognizer); available = true; }
  }
  if (kind == "status") return V(M{{V("handwriting"), V(available)},
      {V("spelling"), V(true)}, {V("recognizers"), V(names)}});
  if (!available) throw std::runtime_error("handwriting_language_missing");
  InkStrokeContainer strokes;
  InkStrokeBuilder builder;
  const auto& source = std::get<L>(Field(args, "strokes"));
  if (source.size() > 2000) throw std::invalid_argument("Too many strokes");
  size_t point_count = 0;
  for (const auto& item : source) {
    const auto& stroke = std::get<M>(item);
    const auto& xs = std::get<L>(Field(stroke, "x"));
    const auto& ys = std::get<L>(Field(stroke, "y"));
    if (xs.size() != ys.size()) throw std::invalid_argument("Invalid stroke");
    point_count += xs.size();
    if (point_count > 250000) throw std::invalid_argument("Too many points");
    std::vector<winrt::Windows::Foundation::Point> points;
    for (size_t i = 0; i < xs.size(); i++) {
      const auto x = Number(xs[i]), y = Number(ys[i]);
      if (!std::isfinite(x) || !std::isfinite(y)) throw std::invalid_argument("Invalid point");
      points.push_back({static_cast<float>(x), static_cast<float>(y)});
    }
    if (points.size() >= 2) strokes.AddStroke(builder.CreateStroke(points));
  }
  L result;
  if (strokes.GetStrokes().Size() == 0) return V(result);
  // This blocking wait is on a dedicated MTA worker, never the UI thread.
  const auto words = recognizers.RecognizeAsync(strokes, InkRecognitionTarget::All).get();
  for (const auto& word : words) {
    const auto candidates = word.GetTextCandidates();
    if (candidates.Size() == 0) continue;
    const auto text = winrt::to_string(candidates.GetAt(0));
    if (Check(checker.get(), text).empty()) continue;
    const auto rect = word.BoundingRect();
    result.emplace_back(M{{V("text"), V(text)}, {V("x"), V(static_cast<double>(rect.X))},
      {V("y"), V(static_cast<double>(rect.Y))}, {V("w"), V(static_cast<double>(rect.Width))},
      {V("h"), V(static_cast<double>(rect.Height))}});
  }
  return V(result);
}
}

struct WritingServices::State {
  std::mutex mutex;
  std::map<int32_t, std::optional<V>> jobs;
  int32_t next = 0;
  int running = 0;
  bool alive = true;
};

WritingServices::WritingServices(flutter::BinaryMessenger* messenger)
    : state_(std::make_shared<State>()),
      channel_(std::make_unique<flutter::MethodChannel<V>>(messenger,
          "openote/writing_services", &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([state = state_](const flutter::MethodCall<V>& call,
      std::unique_ptr<flutter::MethodResult<V>> result) {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (call.method_name() == "poll" || call.method_name() == "cancel") {
      const auto id = call.arguments() ? std::get_if<int32_t>(call.arguments()) : nullptr;
      if (!id) { result->Error("argument", "Expected job id"); return; }
      auto found = state->jobs.find(*id);
      if (call.method_name() == "cancel") { state->jobs.erase(*id); result->Success(); return; }
      if (found == state->jobs.end()) { result->Error("missing", "Job expired"); return; }
      if (!found->second) { result->Success(); return; }
      result->Success(*found->second);
      state->jobs.erase(found);
      return;
    }
    if (call.method_name() != "start") { result->NotImplemented(); return; }
    const auto args = call.arguments() ? std::get_if<M>(call.arguments()) : nullptr;
    if (!args) { result->Error("argument", "Expected arguments"); return; }
    if (state->running >= 2) { result->Error("busy", "Recognition busy"); return; }
    const auto id = ++state->next;
    state->jobs[id] = std::nullopt;
    state->running++;
    try {
    std::thread([state, id, args = *args]() {
      V value;
      try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        try { value = Run(args); }
        catch (...) { winrt::uninit_apartment(); throw; }
        winrt::uninit_apartment();
      } catch (const winrt::hresult_error& e) {
        value = V(M{{V("error"), V(winrt::to_string(e.message()))}});
      } catch (const std::exception& e) {
        value = V(M{{V("error"), V(std::string(e.what()))}});
      } catch (...) { value = V(M{{V("error"), V("Recognition unavailable")}}); }
      std::lock_guard<std::mutex> guard(state->mutex);
      state->running--;
      if (state->alive && state->jobs.count(id)) state->jobs[id] = std::move(value);
    }).detach();
    } catch (const std::exception& e) {
      state->running--;
      state->jobs.erase(id);
      result->Error("worker", e.what());
      return;
    }
    result->Success(V(id));
  });
}
WritingServices::~WritingServices() {
  channel_->SetMethodCallHandler(nullptr);
  std::lock_guard<std::mutex> guard(state_->mutex);
  state_->alive = false;
  state_->jobs.clear();
}
