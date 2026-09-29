#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#include <moonbit.h>

#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

#if defined(_WIN32)
#define GITHUB_CLIENT_TOKEN_NOTE "Encrypted with Windows DPAPI before it is saved."
#elif defined(__APPLE__)
#define GITHUB_CLIENT_TOKEN_NOTE "Encrypted with the macOS Keychain before it is saved."
#else
#define GITHUB_CLIENT_TOKEN_NOTE "Encrypted by the OS credential store before it is saved."
#endif

#include "../../vendor/imgui/imgui.cpp"
#include "../../vendor/imgui/imgui_draw.cpp"
#include "../../vendor/imgui/imgui_tables.cpp"
#include "../../vendor/imgui/imgui_widgets.cpp"
#include "../../vendor/imgui/backends/imgui_impl_glfw.cpp"
#include "../../vendor/imgui/backends/imgui_impl_opengl3.cpp"

// ---------------------------------------------------------------------------
// Palette (GitHub Primer light)

#define GC_FG IM_COL32(31, 35, 40, 255)
#define GC_MUTED IM_COL32(89, 99, 110, 255)
#define GC_SUBTLE IM_COL32(129, 139, 152, 255)
#define GC_BORDER IM_COL32(208, 215, 222, 255)
#define GC_BORDER_MUTED IM_COL32(216, 222, 228, 255)
#define GC_CANVAS IM_COL32(246, 248, 250, 255)
#define GC_HOVER IM_COL32(234, 238, 242, 255)
#define GC_WHITE IM_COL32(255, 255, 255, 255)
#define GC_ACCENT IM_COL32(9, 105, 218, 255)
#define GC_ACCENT_EMPHASIS IM_COL32(5, 80, 174, 255)
#define GC_ACCENT_SUBTLE IM_COL32(221, 244, 255, 255)
#define GC_ACCENT_BORDER IM_COL32(84, 174, 255, 255)
#define GC_SUCCESS IM_COL32(26, 127, 55, 255)
#define GC_SUCCESS_BUTTON IM_COL32(31, 136, 61, 255)
#define GC_SUCCESS_SUBTLE IM_COL32(218, 251, 225, 255)
#define GC_SUCCESS_BORDER IM_COL32(74, 194, 107, 255)
#define GC_DANGER IM_COL32(209, 36, 47, 255)
#define GC_DANGER_BUTTON IM_COL32(207, 34, 46, 255)
#define GC_DANGER_SUBTLE IM_COL32(255, 235, 233, 255)
#define GC_DANGER_BORDER IM_COL32(255, 129, 130, 255)
#define GC_ATTENTION IM_COL32(154, 103, 0, 255)
#define GC_ATTENTION_SUBTLE IM_COL32(255, 248, 197, 255)
#define GC_ATTENTION_BORDER IM_COL32(212, 167, 44, 255)
#define GC_DONE IM_COL32(130, 80, 223, 255)
#define GC_DONE_SUBTLE IM_COL32(251, 239, 255, 255)
#define GC_DONE_BORDER IM_COL32(194, 151, 255, 255)
#define GC_SNACKBAR IM_COL32(37, 41, 46, 255)

static ImU32 gc_alpha(ImU32 color, float alpha) {
  const int a = static_cast<int>(((color >> IM_COL32_A_SHIFT) & 0xFF) * ImClamp(alpha, 0.0f, 1.0f));
  return (color & ~IM_COL32_A_MASK) | (static_cast<ImU32>(a) << IM_COL32_A_SHIFT);
}

// ---------------------------------------------------------------------------
// Fonts

static ImFont* gc_font_regular = nullptr;
static ImFont* gc_font_bold = nullptr;
static ImFont* gc_font_mono = nullptr;

static const float GC_BODY = 14.0f;
static const float GC_SMALL = 12.5f;
static const float GC_TITLE = 25.0f;

static ImFont* gc_load_font(const char* primary, const char* japanese) {
  ImGuiIO& io = ImGui::GetIO();
  ImFont* font = io.Fonts->AddFontFromFileTTF(primary, GC_BODY);
  if (font != nullptr && japanese != nullptr) {
    ImFontConfig merge;
    merge.MergeMode = true;
    io.Fonts->AddFontFromFileTTF(japanese, GC_BODY, &merge);
  }
  return font;
}

static void github_client_load_fonts() {
  ImGuiIO& io = ImGui::GetIO();
  io.IniFilename = nullptr;
#ifdef _WIN32
  gc_font_regular = gc_load_font("C:\\Windows\\Fonts\\segoeui.ttf", "C:\\Windows\\Fonts\\meiryo.ttc");
  gc_font_bold = gc_load_font("C:\\Windows\\Fonts\\segoeuib.ttf", "C:\\Windows\\Fonts\\meiryob.ttc");
  gc_font_mono = gc_load_font("C:\\Windows\\Fonts\\consola.ttf", nullptr);
#endif
#ifdef __APPLE__
  // "ヒラギノ角ゴシック W3/W6" spelled in UTF-8.
  gc_font_regular = gc_load_font(
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/\xE3\x83\x92\xE3\x83\xA9\xE3\x82\xAE\xE3\x83\x8E\xE8\xA7\x92\xE3\x82\xB4\xE3\x82\xB7\xE3\x83\x83\xE3\x82\xAF W3.ttc"
  );
  // SF is a variable font whose default instance is Regular, so bold text
  // uses Hiragino Sans W6, which covers Latin and Japanese.
  gc_font_bold = gc_load_font(
    "/System/Library/Fonts/\xE3\x83\x92\xE3\x83\xA9\xE3\x82\xAE\xE3\x83\x8E\xE8\xA7\x92\xE3\x82\xB4\xE3\x82\xB7\xE3\x83\x83\xE3\x82\xAF W6.ttc",
    nullptr
  );
  gc_font_mono = gc_load_font("/System/Library/Fonts/SFNSMono.ttf", nullptr);
#endif
  if (gc_font_regular == nullptr) gc_font_regular = io.Fonts->AddFontDefault();
  if (gc_font_bold == nullptr) gc_font_bold = gc_font_regular;
  if (gc_font_mono == nullptr) gc_font_mono = gc_font_regular;
  io.FontDefault = gc_font_regular;
}

static void github_client_apply_theme() {
  ImGuiStyle& style = ImGui::GetStyle();
  ImGui::StyleColorsLight();
  style.WindowPadding = ImVec2(0.0f, 0.0f);
  style.FramePadding = ImVec2(10.0f, 7.0f);
  style.ItemSpacing = ImVec2(8.0f, 8.0f);
  style.ItemInnerSpacing = ImVec2(8.0f, 6.0f);
  style.ScrollbarSize = 10.0f;
  style.WindowRounding = 0.0f;
  style.ChildRounding = 0.0f;
  style.FrameRounding = 6.0f;
  style.PopupRounding = 12.0f;
  style.ScrollbarRounding = 8.0f;
  style.GrabRounding = 6.0f;
  style.WindowBorderSize = 0.0f;
  style.ChildBorderSize = 1.0f;
  style.PopupBorderSize = 1.0f;
  style.FrameBorderSize = 1.0f;
  ImVec4* colors = style.Colors;
  colors[ImGuiCol_Text] = ImGui::ColorConvertU32ToFloat4(GC_FG);
  colors[ImGuiCol_TextDisabled] = ImGui::ColorConvertU32ToFloat4(GC_MUTED);
  colors[ImGuiCol_WindowBg] = ImGui::ColorConvertU32ToFloat4(GC_CANVAS);
  colors[ImGuiCol_ChildBg] = ImVec4(0, 0, 0, 0);
  colors[ImGuiCol_PopupBg] = ImGui::ColorConvertU32ToFloat4(GC_WHITE);
  colors[ImGuiCol_Border] = ImGui::ColorConvertU32ToFloat4(GC_BORDER);
  colors[ImGuiCol_FrameBg] = ImGui::ColorConvertU32ToFloat4(GC_WHITE);
  colors[ImGuiCol_FrameBgHovered] = ImGui::ColorConvertU32ToFloat4(GC_WHITE);
  colors[ImGuiCol_FrameBgActive] = ImGui::ColorConvertU32ToFloat4(GC_WHITE);
  colors[ImGuiCol_Button] = ImGui::ColorConvertU32ToFloat4(GC_CANVAS);
  colors[ImGuiCol_ButtonHovered] = ImGui::ColorConvertU32ToFloat4(GC_HOVER);
  colors[ImGuiCol_ButtonActive] = ImGui::ColorConvertU32ToFloat4(GC_BORDER);
  colors[ImGuiCol_Header] = ImGui::ColorConvertU32ToFloat4(GC_ACCENT_SUBTLE);
  colors[ImGuiCol_HeaderHovered] = ImGui::ColorConvertU32ToFloat4(GC_HOVER);
  colors[ImGuiCol_HeaderActive] = ImGui::ColorConvertU32ToFloat4(GC_ACCENT_SUBTLE);
  colors[ImGuiCol_CheckMark] = ImGui::ColorConvertU32ToFloat4(GC_ACCENT);
  colors[ImGuiCol_ScrollbarBg] = ImVec4(0, 0, 0, 0);
  colors[ImGuiCol_ScrollbarGrab] = ImGui::ColorConvertU32ToFloat4(IM_COL32(175, 184, 193, 255));
  colors[ImGuiCol_Separator] = ImGui::ColorConvertU32ToFloat4(GC_BORDER_MUTED);
  colors[ImGuiCol_ModalWindowDimBg] = ImGui::ColorConvertU32ToFloat4(IM_COL32(31, 35, 40, 82));
}

extern "C" int github_client_imgui_init(GLFWwindow* window) {
  if (window == nullptr) return 0;
  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  github_client_apply_theme();
  github_client_load_fonts();
  if (!ImGui_ImplGlfw_InitForOpenGL(window, true)) {
    ImGui::DestroyContext();
    return 0;
  }
#ifdef __APPLE__
  const char* glsl_version = "#version 150";
#else
  const char* glsl_version = "#version 330";
#endif
  if (!ImGui_ImplOpenGL3_Init(glsl_version)) {
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    return 0;
  }
  return 1;
}

// ---------------------------------------------------------------------------
// Strings

static std::string gc_utf8(const uint16_t* source) {
  std::string result;
  if (source == nullptr) return result;
  const int32_t length = Moonbit_array_length(source);
  for (int32_t index = 0; index < length; ++index) {
    uint32_t codepoint = source[index];
    if (codepoint >= 0xD800 && codepoint <= 0xDBFF && index + 1 < length) {
      const uint32_t low = source[index + 1];
      if (low >= 0xDC00 && low <= 0xDFFF) {
        codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
        ++index;
      }
    }
    if (codepoint < 0x80) {
      result.push_back(static_cast<char>(codepoint));
    } else if (codepoint < 0x800) {
      result.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
      result.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else if (codepoint < 0x10000) {
      result.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
      result.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
      result.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else {
      result.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
      result.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
      result.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
      result.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    }
  }
  return result;
}

static moonbit_string_t gc_moonbit_string(const std::string& value) {
  std::vector<uint16_t> units;
  size_t index = 0;
  while (index < value.size()) {
    const unsigned char lead = static_cast<unsigned char>(value[index]);
    uint32_t codepoint = lead;
    size_t extra = 0;
    if (lead >= 0xF0) { codepoint = lead & 0x07; extra = 3; }
    else if (lead >= 0xE0) { codepoint = lead & 0x0F; extra = 2; }
    else if (lead >= 0xC0) { codepoint = lead & 0x1F; extra = 1; }
    for (size_t k = 1; k <= extra && index + k < value.size(); ++k) {
      codepoint = (codepoint << 6) | (static_cast<unsigned char>(value[index + k]) & 0x3F);
    }
    index += extra + 1;
    if (codepoint >= 0x10000) {
      codepoint -= 0x10000;
      units.push_back(static_cast<uint16_t>(0xD800 + (codepoint >> 10)));
      units.push_back(static_cast<uint16_t>(0xDC00 + (codepoint & 0x3FF)));
    } else {
      units.push_back(static_cast<uint16_t>(codepoint));
    }
  }
  moonbit_string_t result = moonbit_make_string(static_cast<int32_t>(units.size()), 0);
  for (size_t k = 0; k < units.size(); ++k) result[k] = units[k];
  return result;
}

static std::vector<std::string> gc_split(const std::string& value, char separator) {
  std::vector<std::string> parts;
  size_t start = 0;
  while (true) {
    const size_t end = value.find(separator, start);
    parts.push_back(value.substr(start, end == std::string::npos ? std::string::npos : end - start));
    if (end == std::string::npos) break;
    start = end + 1;
  }
  return parts;
}

static std::vector<std::vector<std::string>> gc_lines(const uint16_t* source) {
  std::vector<std::vector<std::string>> lines;
  for (const std::string& line : gc_split(gc_utf8(source), '\n')) {
    if (!line.empty()) lines.push_back(gc_split(line, '\t'));
  }
  return lines;
}

static std::string gc_field(const std::vector<std::string>& fields, size_t index) {
  return index < fields.size() ? fields[index] : std::string();
}

static int gc_int_field(const std::vector<std::string>& fields, size_t index) {
  return std::atoi(gc_field(fields, index).c_str());
}

static bool gc_contains_ci(const std::string& haystack, const char* needle) {
  std::string h = haystack;
  std::string n = needle;
  for (char& c : h) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  for (char& c : n) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return h.find(n) != std::string::npos;
}

// ---------------------------------------------------------------------------
// Icons, drawn on a 16-unit grid

enum GcIcon {
  GC_ICON_PR, GC_ICON_PR_DRAFT, GC_ICON_ISSUE, GC_ICON_BUNDLE, GC_ICON_CHECK,
  GC_ICON_INBOX, GC_ICON_AT, GC_ICON_BOOKMARK, GC_ICON_BOOKMARK_FILLED,
  GC_ICON_REPO, GC_ICON_GEAR, GC_ICON_REFRESH, GC_ICON_SEARCH, GC_ICON_KEBAB,
  GC_ICON_CHEVRON_DOWN, GC_ICON_CHEVRON_UP, GC_ICON_CLOSE, GC_ICON_INFO,
  GC_ICON_WARNING, GC_ICON_ERROR, GC_ICON_OFFLINE, GC_ICON_LINK,
  GC_ICON_BELL_OFF, GC_ICON_LOCK, GC_ICON_CHECK_CIRCLE, GC_ICON_NONE
};

static void gc_icon(ImDrawList* draw, GcIcon icon, ImVec2 origin, float size, ImU32 color) {
  const float s = size / 16.0f;
  const float t = 1.5f * s;
  auto p = [&](float x, float y) { return ImVec2(origin.x + x * s, origin.y + y * s); };
  auto line = [&](float x1, float y1, float x2, float y2) { draw->AddLine(p(x1, y1), p(x2, y2), color, t); };
  auto ring = [&](float x, float y, float r) { draw->AddCircle(p(x, y), r * s, color, 24, t); };
  auto dot = [&](float x, float y, float r) { draw->AddCircleFilled(p(x, y), r * s, color, 12); };
  switch (icon) {
    case GC_ICON_PR:
      ring(4, 3.5f, 1.75f); ring(4, 12.5f, 1.75f); ring(12, 12.5f, 1.75f);
      line(4, 5.25f, 4, 10.75f); line(12, 10.75f, 12, 6.5f);
      draw->PathArcTo(p(10, 6.5f), 2 * s, 0.0f, -IM_PI * 0.5f, 8);
      draw->PathLineTo(p(7.5f, 4.5f));
      draw->PathStroke(color, 0, t);
      line(7.5f, 4.5f, 9, 3); line(7.5f, 4.5f, 9, 6);
      break;
    case GC_ICON_PR_DRAFT:
      ring(4, 3.5f, 1.75f); ring(4, 12.5f, 1.75f); ring(12, 12.5f, 1.75f);
      line(4, 5.25f, 4, 10.75f);
      dot(12, 9, 0.8f); dot(12, 6.2f, 0.8f); dot(12, 3.5f, 0.8f);
      break;
    case GC_ICON_ISSUE:
      ring(8, 8, 6.25f); dot(8, 8, 1.4f);
      break;
    case GC_ICON_BUNDLE:
      draw->PathLineTo(p(8, 1.75f)); draw->PathLineTo(p(13.5f, 4.75f));
      draw->PathLineTo(p(13.5f, 11.25f)); draw->PathLineTo(p(8, 14.25f));
      draw->PathLineTo(p(2.5f, 11.25f)); draw->PathLineTo(p(2.5f, 4.75f));
      draw->PathStroke(color, ImDrawFlags_Closed, t);
      line(2.5f, 4.75f, 8, 7.75f); line(8, 7.75f, 13.5f, 4.75f); line(8, 7.75f, 8, 14.25f);
      break;
    case GC_ICON_CHECK:
      draw->PathLineTo(p(3, 8.5f)); draw->PathLineTo(p(6.5f, 12)); draw->PathLineTo(p(13, 4.5f));
      draw->PathStroke(color, 0, 1.75f * s);
      break;
    case GC_ICON_INBOX:
      draw->PathLineTo(p(3.75f, 3.25f)); draw->PathLineTo(p(12.25f, 3.25f));
      draw->PathLineTo(p(14, 9.5f)); draw->PathLineTo(p(14, 12.75f));
      draw->PathLineTo(p(2, 12.75f)); draw->PathLineTo(p(2, 9.5f));
      draw->PathStroke(color, ImDrawFlags_Closed, t);
      draw->PathLineTo(p(2.5f, 9.5f)); draw->PathLineTo(p(5.5f, 9.5f));
      draw->PathLineTo(p(6.5f, 11.25f)); draw->PathLineTo(p(9.5f, 11.25f));
      draw->PathLineTo(p(10.5f, 9.5f)); draw->PathLineTo(p(13.5f, 9.5f));
      draw->PathStroke(color, 0, t);
      break;
    case GC_ICON_AT:
      ring(8, 8, 2.5f);
      draw->PathArcTo(p(8, 8), 6 * s, 0.0f, IM_PI * 1.75f, 24);
      draw->PathStroke(color, 0, t);
      line(10.5f, 6.5f, 10.5f, 9); line(10.5f, 9, 12, 10.25f); line(12, 10.25f, 14, 9);
      break;
    case GC_ICON_BOOKMARK:
    case GC_ICON_BOOKMARK_FILLED:
      draw->PathLineTo(p(4, 2.5f)); draw->PathLineTo(p(12, 2.5f));
      draw->PathLineTo(p(12, 13.5f)); draw->PathLineTo(p(8, 10.75f));
      draw->PathLineTo(p(4, 13.5f));
      if (icon == GC_ICON_BOOKMARK_FILLED) draw->PathFillConcave(color);
      else draw->PathStroke(color, ImDrawFlags_Closed, t);
      break;
    case GC_ICON_REPO:
      draw->PathLineTo(p(3.5f, 13)); draw->PathLineTo(p(3.5f, 3));
      draw->PathLineTo(p(4.5f, 2)); draw->PathLineTo(p(12.5f, 2));
      draw->PathLineTo(p(12.5f, 11.5f)); draw->PathLineTo(p(5, 11.5f));
      draw->PathStroke(color, 0, t);
      line(3.5f, 13, 5, 14.5f); line(5, 14.5f, 12.5f, 14.5f); line(12.5f, 14.5f, 12.5f, 11.5f);
      break;
    case GC_ICON_GEAR:
      ring(8, 8, 2.25f);
      for (int k = 0; k < 8; ++k) {
        const float a = k * IM_PI / 4.0f;
        line(8 + std::cos(a) * 4.5f, 8 + std::sin(a) * 4.5f, 8 + std::cos(a) * 6.5f, 8 + std::sin(a) * 6.5f);
      }
      ring(8, 8, 4.5f);
      break;
    case GC_ICON_REFRESH:
      draw->PathArcTo(p(8, 8), 5.25f * s, -IM_PI * 0.25f, IM_PI * 1.55f, 24);
      draw->PathStroke(color, 0, t);
      line(12.2f, 2.3f, 12.2f, 4.7f); line(12.2f, 4.7f, 9.8f, 4.7f);
      break;
    case GC_ICON_SEARCH:
      ring(7, 7, 4.25f); line(10.25f, 10.25f, 13.25f, 13.25f);
      break;
    case GC_ICON_KEBAB:
      dot(3, 8, 1.3f); dot(8, 8, 1.3f); dot(13, 8, 1.3f);
      break;
    case GC_ICON_CHEVRON_DOWN:
      draw->PathLineTo(p(4, 6)); draw->PathLineTo(p(8, 10)); draw->PathLineTo(p(12, 6));
      draw->PathStroke(color, 0, 1.75f * s);
      break;
    case GC_ICON_CHEVRON_UP:
      draw->PathLineTo(p(4, 10)); draw->PathLineTo(p(8, 6)); draw->PathLineTo(p(12, 10));
      draw->PathStroke(color, 0, 1.75f * s);
      break;
    case GC_ICON_CLOSE:
      line(4, 4, 12, 12); line(12, 4, 4, 12);
      break;
    case GC_ICON_INFO:
      ring(8, 8, 6.25f); line(8, 7.25f, 8, 11.25f); dot(8, 4.9f, 0.9f);
      break;
    case GC_ICON_WARNING:
      draw->PathLineTo(p(8, 1.75f)); draw->PathLineTo(p(14.75f, 13.5f)); draw->PathLineTo(p(1.25f, 13.5f));
      draw->PathStroke(color, ImDrawFlags_Closed, t);
      line(8, 6.25f, 8, 9.75f); dot(8, 11.6f, 0.9f);
      break;
    case GC_ICON_ERROR:
      ring(8, 8, 6.25f); line(8, 4.75f, 8, 8.5f); dot(8, 11, 0.9f);
      break;
    case GC_ICON_OFFLINE:
      draw->PathArcTo(p(8, 12.5f), 9 * s, -IM_PI * 0.78f, -IM_PI * 0.22f, 16); draw->PathStroke(color, 0, t);
      draw->PathArcTo(p(8, 12.5f), 5.75f * s, -IM_PI * 0.75f, -IM_PI * 0.25f, 12); draw->PathStroke(color, 0, t);
      dot(8, 12.25f, 1.1f); line(2.5f, 2.5f, 13.5f, 13.5f);
      break;
    case GC_ICON_LINK:
      line(6.5f, 9.5f, 9.5f, 6.5f);
      draw->PathArcTo(p(10.5f, 5.5f), 2.5f * s, IM_PI * 0.75f, IM_PI * 2.25f, 12); draw->PathStroke(color, 0, t);
      draw->PathArcTo(p(5.5f, 10.5f), 2.5f * s, -IM_PI * 0.25f, IM_PI * 1.25f, 12); draw->PathStroke(color, 0, t);
      break;
    case GC_ICON_BELL_OFF:
      draw->PathArcTo(p(8, 7), 4 * s, IM_PI, IM_PI * 2.0f, 12);
      draw->PathLineTo(p(12, 11)); draw->PathLineTo(p(4, 11));
      draw->PathStroke(color, ImDrawFlags_Closed, t);
      line(6, 13.5f, 10, 13.5f); line(2.5f, 2.5f, 13.5f, 13.5f);
      break;
    case GC_ICON_LOCK:
      draw->AddRect(p(3.25f, 7), p(12.75f, 13.5f), color, 1.5f * s, 0, t);
      draw->PathArcTo(p(8, 5), 2.5f * s, IM_PI, IM_PI * 2.0f, 12);
      draw->PathStroke(color, 0, t);
      line(5.5f, 5, 5.5f, 7); line(10.5f, 5, 10.5f, 7);
      break;
    case GC_ICON_CHECK_CIRCLE:
      ring(8, 8, 6.25f);
      draw->PathLineTo(p(5, 8.25f)); draw->PathLineTo(p(7, 10.25f)); draw->PathLineTo(p(11, 6));
      draw->PathStroke(color, 0, t);
      break;
    case GC_ICON_NONE:
      break;
  }
}

// ---------------------------------------------------------------------------
// Text and controls

// Hiragino W6 draws noticeably larger than SF at the same pixel size, so
// bold text is scaled down to match the regular face.
static float gc_fs(ImFont* font, float size) { return font == gc_font_bold ? size * 0.86f : size; }

static void gc_font(ImFont* font, float size) { ImGui::PushFont(font, gc_fs(font, size)); }
static void gc_pop_font() { ImGui::PopFont(); }

static ImVec2 gc_text_size(ImFont* font, float size, const std::string& text) {
  return font->CalcTextSizeA(gc_fs(font, size), FLT_MAX, 0.0f, text.c_str());
}

static void gc_text(ImDrawList* draw, ImFont* font, float size, ImVec2 pos, ImU32 color, const std::string& text) {
  draw->AddText(font, gc_fs(font, size), pos, color, text.c_str());
}

// Single-line text clipped to `max_x` with an ellipsis.
static void gc_text_ellipsis(ImFont* font, float size, ImVec2 pos, float max_x, ImU32 color, const std::string& text) {
  gc_font(font, size);
  ImGui::PushStyleColor(ImGuiCol_Text, color);
  const float height = ImGui::GetFontSize();
  ImGui::RenderTextEllipsis(ImGui::GetWindowDrawList(), pos, ImVec2(max_x, pos.y + height + 2.0f), max_x,
                            text.c_str(), nullptr, nullptr);
  ImGui::PopStyleColor();
  gc_pop_font();
}

enum GcButtonKind { GC_BUTTON_DEFAULT, GC_BUTTON_PRIMARY, GC_BUTTON_DANGER, GC_BUTTON_DANGER_SOLID, GC_BUTTON_PLAIN, GC_BUTTON_LINK };

static float gc_button_width(const char* label, GcIcon icon, float height = 32.0f) {
  if (!label[0]) return height;
  const float text = gc_text_size(gc_font_regular, 13.0f, label).x;
  const float icon_w = icon != GC_ICON_NONE ? 22.0f : 0.0f;
  return text + icon_w + 24.0f;
}

// A labelled button drawn in the Primer style. Returns true when pressed.
static bool gc_button(const char* id, const char* label, GcButtonKind kind, GcIcon icon = GC_ICON_NONE,
                      bool disabled = false, float width = 0.0f, float height = 32.0f) {
  const float w = width > 0.0f ? width : gc_button_width(label, icon, height);
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  ImGui::BeginDisabled(disabled);
  const bool pressed = ImGui::InvisibleButton(id, ImVec2(w, height));
  ImGui::EndDisabled();
  const bool hovered = !disabled && ImGui::IsItemHovered();
  const bool active = !disabled && ImGui::IsItemActive();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  ImU32 bg = GC_CANVAS, border = GC_BORDER, fg = GC_FG;
  switch (kind) {
    case GC_BUTTON_DEFAULT: bg = active ? GC_BORDER_MUTED : hovered ? GC_HOVER : GC_CANVAS; break;
    case GC_BUTTON_PLAIN: bg = active ? GC_HOVER : hovered ? GC_CANVAS : GC_WHITE; break;
    case GC_BUTTON_PRIMARY:
      bg = active ? IM_COL32(25, 116, 50, 255) : hovered ? GC_SUCCESS : GC_SUCCESS_BUTTON;
      border = IM_COL32(26, 127, 55, 255); fg = GC_WHITE; break;
    case GC_BUTTON_DANGER:
      bg = active ? IM_COL32(255, 206, 203, 255) : hovered ? GC_DANGER_SUBTLE : GC_WHITE;
      border = hovered ? GC_DANGER_BORDER : GC_BORDER; fg = GC_DANGER_BUTTON; break;
    case GC_BUTTON_DANGER_SOLID:
      bg = active ? IM_COL32(164, 14, 38, 255) : hovered ? IM_COL32(180, 20, 40, 255) : GC_DANGER_BUTTON;
      border = IM_COL32(164, 14, 38, 255); fg = GC_WHITE; break;
    case GC_BUTTON_LINK:
      bg = hovered ? GC_CANVAS : 0; border = 0; fg = GC_ACCENT; break;
  }
  const float alpha = disabled ? 0.55f : 1.0f;
  if (bg) draw->AddRectFilled(pos, ImVec2(pos.x + w, pos.y + height), gc_alpha(bg, alpha), 6.0f);
  if (border) draw->AddRect(pos, ImVec2(pos.x + w, pos.y + height), gc_alpha(border, alpha), 6.0f);
  const float text_w = label[0] ? gc_text_size(gc_font_regular, 13.0f, label).x : 0.0f;
  const float icon_w = icon != GC_ICON_NONE ? 16.0f : 0.0f;
  const float gap = (label[0] && icon != GC_ICON_NONE) ? 6.0f : 0.0f;
  float x = pos.x + (w - (text_w + icon_w + gap)) * 0.5f;
  if (icon != GC_ICON_NONE) {
    gc_icon(draw, icon, ImVec2(x, pos.y + (height - 16.0f) * 0.5f), 16.0f, gc_alpha(fg, alpha));
    x += icon_w + gap;
  }
  if (label[0]) {
    gc_text(draw, gc_font_regular, 13.0f, ImVec2(x, pos.y + (height - 13.0f) * 0.5f - 1.0f), gc_alpha(fg, alpha), label);
  }
  return pressed && !disabled;
}

// Transparent square icon button (Save, More actions, Dismiss).
static bool gc_icon_button(const char* id, GcIcon icon, ImU32 color, float size = 32.0f) {
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  const bool pressed = ImGui::InvisibleButton(id, ImVec2(size, size));
  const bool hovered = ImGui::IsItemHovered();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  if (hovered) draw->AddRectFilled(pos, ImVec2(pos.x + size, pos.y + size), GC_HOVER, 6.0f);
  gc_icon(draw, icon, ImVec2(pos.x + (size - 16.0f) * 0.5f, pos.y + (size - 16.0f) * 0.5f), 16.0f, color);
  return pressed;
}

static float gc_pill(ImDrawList* draw, ImVec2 pos, const std::string& text, ImU32 fg, ImU32 bg, ImU32 border) {
  const ImVec2 size = gc_text_size(gc_font_regular, 12.0f, text);
  const float w = size.x + 16.0f;
  const float h = 20.0f;
  draw->AddRectFilled(pos, ImVec2(pos.x + w, pos.y + h), bg, h * 0.5f);
  draw->AddRect(pos, ImVec2(pos.x + w, pos.y + h), border, h * 0.5f);
  gc_text(draw, gc_font_regular, 12.0f, ImVec2(pos.x + 8.0f, pos.y + (h - 12.0f) * 0.5f - 1.0f), fg, text);
  return w;
}

static void gc_reason_colors(const std::string& reason, bool muted, ImU32* fg, ImU32* bg, ImU32* border) {
  const float a = muted ? 0.6f : 1.0f;
  if (reason == "Review requested") { *fg = GC_ACCENT; *bg = GC_ACCENT_SUBTLE; *border = GC_ACCENT_BORDER; }
  else if (reason == "Assigned") { *fg = GC_SUCCESS; *bg = GC_SUCCESS_SUBTLE; *border = GC_SUCCESS_BORDER; }
  else if (reason == "Mentioned") { *fg = GC_DONE; *bg = GC_DONE_SUBTLE; *border = GC_DONE_BORDER; }
  else if (reason == "Still needs your review") { *fg = GC_ATTENTION; *bg = GC_ATTENTION_SUBTLE; *border = GC_ATTENTION_BORDER; }
  else { *fg = GC_MUTED; *bg = GC_CANVAS; *border = GC_BORDER; }
  *fg = gc_alpha(*fg, a); *bg = gc_alpha(*bg, a); *border = gc_alpha(*border, a);
}

static float gc_ease_in_out(float x) {
  return x < 0.5f ? 4.0f * x * x * x : 1.0f - std::pow(-2.0f * x + 2.0f, 3.0f) / 2.0f;
}

static float gc_ease_out(float t) {
  t = ImClamp(t, 0.0f, 1.0f);
  return 1.0f - (1.0f - t) * (1.0f - t) * (1.0f - t);
}

// Material 3 indeterminate circular progress indicator.
static void gc_spinner(ImDrawList* draw, ImVec2 center, float radius, float thickness, double time,
                       ImU32 track = GC_ACCENT_SUBTLE, ImU32 color = GC_ACCENT) {
  const double cycle_seconds = 1.333;
  const float min_sweep = 0.08f * IM_PI;
  const float extra_sweep = 1.42f * IM_PI;
  const double cycles = time / cycle_seconds;
  const double cycle_index = std::floor(cycles);
  const float phase = static_cast<float>(cycles - cycle_index);
  float head = extra_sweep, tail = 0.0f;
  if (phase < 0.5f) head = gc_ease_in_out(phase * 2.0f) * extra_sweep;
  else tail = gc_ease_in_out((phase - 0.5f) * 2.0f) * extra_sweep;
  // Each cycle starts where the previous tail stopped, so the arc never jumps.
  const float base = static_cast<float>(time * 2.0 * IM_PI * 0.55 + cycle_index * extra_sweep) - IM_PI * 0.5f;
  if (track) draw->AddCircle(center, radius, track, 48, thickness);
  draw->PathArcTo(center, radius, base + tail, base + head + min_sweep, 40);
  draw->PathStroke(color, 0, thickness);
}

// Linear progress: determinate when total > 0, otherwise indeterminate.
static void gc_progress_bar(ImDrawList* draw, ImVec2 min, ImVec2 max, int done, int total, double time) {
  const float rounding = (max.y - min.y) * 0.5f;
  draw->AddRectFilled(min, max, GC_ACCENT_SUBTLE, rounding);
  const float width = max.x - min.x;
  if (total > 0) {
    const float fraction = ImClamp(static_cast<float>(done) / static_cast<float>(total), 0.0f, 1.0f);
    if (fraction > 0.0f) draw->AddRectFilled(min, ImVec2(min.x + width * fraction, max.y), GC_ACCENT, rounding);
    return;
  }
  const float eased = gc_ease_in_out(static_cast<float>(std::fmod(time, 1.8) / 1.8));
  const float start = ImClamp(eased * 1.4f - 0.4f, 0.0f, 1.0f);
  const float end = ImClamp(eased * 1.4f, 0.0f, 1.0f);
  if (end > start) draw->AddRectFilled(ImVec2(min.x + width * start, min.y), ImVec2(min.x + width * end, max.y), GC_ACCENT, rounding);
}

// ---------------------------------------------------------------------------
// View state owned by the bridge: filters, inputs, and transient UI. Product
// rules (which rows exist, grouping, bundling) stay in MoonBit.

static int gc_view_kind = 0;
static std::string gc_view_repository;
static char gc_query_input[256] = "";
static std::string gc_view_reason;
static bool gc_show_done = false;
static bool gc_auto_refresh_enabled = true;

static char gc_repository_input[256] = "";
static char gc_suggestion_filter[256] = "";
static char gc_scope_input[128] = "";
static char gc_token_input[512] = "";

static std::string gc_selected_url;
static std::string gc_selected_updated_at;
static std::string gc_selected_repository;
static std::string gc_selected_credential;
static std::string gc_selected_key;
static std::string gc_watch_request;

static std::string gc_menu_url;
static std::string gc_menu_repository;
static ImVec2 gc_menu_anchor;
static bool gc_menu_request = false;

static std::string gc_confirm_scope;
static bool gc_confirm_request = false;

static int gc_snack_seq_seen = -1;
static double gc_snack_since = -100.0;
static bool gc_snack_hidden = true;
static int gc_alert_seq_seen = 0;
static int gc_token_open_seen = 0;
static int gc_token_close_seen = 0;

static bool gc_modal_visible = false;
static double gc_modal_busy_since = -1.0;
static double gc_modal_shown_at = -1.0;

static int gc_last_page = -1;
static double gc_page_changed_at = -100.0;

// ---------------------------------------------------------------------------
// Frame input from MoonBit

struct GcFrame {
  int page = 0;
  int busy = 0;
  int progress_done = 0;
  int progress_total = 0;
  bool has_credentials = false;
  bool cancellable = false;
  std::vector<std::string> nav;
  std::vector<std::string> header;
  std::vector<std::vector<std::string>> rows;
  std::vector<std::vector<std::string>> repositories;
  std::vector<std::vector<std::string>> suggestions;
  std::vector<std::vector<std::string>> credentials;
  std::vector<std::vector<std::string>> banners;
  std::vector<std::string> loading;
  std::vector<std::string> snackbar;
  std::vector<std::string> alert;
  std::vector<std::string> token;
  std::vector<std::string> page_error;
};

static std::vector<std::string> gc_fields(const uint16_t* source) {
  return gc_split(gc_utf8(source), '\t');
}

// ---------------------------------------------------------------------------
// Navigation rail

static bool gc_nav_item(const char* id, const char* label, GcIcon icon, bool selected, int count, bool emphasize, bool quiet_count) {
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  const float w = 208.0f, h = 40.0f;
  const bool pressed = ImGui::InvisibleButton(id, ImVec2(w, h));
  const bool hovered = ImGui::IsItemHovered();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  if (selected || hovered) draw->AddRectFilled(pos, ImVec2(pos.x + w, pos.y + h), selected ? GC_ACCENT_SUBTLE : GC_HOVER, 8.0f);
  if (selected) draw->AddRectFilled(ImVec2(pos.x - 8.0f, pos.y + 10.0f), ImVec2(pos.x - 5.0f, pos.y + h - 10.0f), GC_ACCENT, 2.0f);
  gc_icon(draw, icon, ImVec2(pos.x + 12.0f, pos.y + 12.0f), 16.0f, selected ? GC_FG : GC_MUTED);
  gc_text(draw, selected ? gc_font_bold : gc_font_regular, GC_BODY, ImVec2(pos.x + 38.0f, pos.y + 11.0f), GC_FG, label);
  if (count > 0) {
    char text[16];
    std::snprintf(text, sizeof(text), "%d", count);
    if (quiet_count) {
      gc_text(draw, gc_font_regular, 12.0f, ImVec2(pos.x + w - 12.0f - gc_text_size(gc_font_regular, 12.0f, text).x, pos.y + 13.0f), GC_MUTED, text);
    } else {
      const float tw = gc_text_size(gc_font_bold, 12.0f, text).x;
      const float bw = ImMax(20.0f, tw + 14.0f);
      const ImVec2 bmin(pos.x + w - 10.0f - bw, pos.y + 10.0f);
      draw->AddRectFilled(bmin, ImVec2(bmin.x + bw, bmin.y + 20.0f), emphasize ? GC_ACCENT : IM_COL32(175, 184, 193, 255), 10.0f);
      gc_text(draw, gc_font_bold, 12.0f, ImVec2(bmin.x + (bw - tw) * 0.5f, bmin.y + 3.0f), emphasize ? GC_WHITE : GC_FG, text);
    }
  }
  return pressed;
}

static int gc_render_nav(const GcFrame& frame, float height) {
  int action = 0;
  ImGui::SetCursorPos(ImVec2(0.0f, 0.0f));
  ImGui::BeginChild("##nav", ImVec2(232.0f, height), ImGuiChildFlags_None, ImGuiWindowFlags_NoScrollbar);
  ImDrawList* draw = ImGui::GetWindowDrawList();
  const ImVec2 origin = ImGui::GetWindowPos();
  draw->AddRectFilled(ImVec2(origin.x + 20.0f, origin.y + 20.0f), ImVec2(origin.x + 52.0f, origin.y + 52.0f), IM_COL32(37, 41, 46, 255), 8.0f);
  gc_text(draw, gc_font_bold, 13.0f, ImVec2(origin.x + 26.0f, origin.y + 28.0f), GC_WHITE, "GH");
  gc_text(draw, gc_font_bold, GC_BODY, ImVec2(origin.x + 62.0f, origin.y + 18.0f), GC_FG, "GitHub Client");
  const std::string login = gc_field(frame.nav, 3);
  gc_text(draw, gc_font_regular, 12.0f, ImVec2(origin.x + 62.0f, origin.y + 38.0f), GC_MUTED, login.empty() ? std::string("Not connected") : ("@" + login));
  const int page = frame.page;
  float y = 76.0f;
  auto place = [&]() { ImGui::SetCursorPos(ImVec2(12.0f, y)); y += 42.0f; };
  place(); if (gc_nav_item("##nav.inbox", "Inbox", GC_ICON_INBOX, page == 0, gc_int_field(frame.nav, 0), page == 0, false)) action = 10;
  place(); if (gc_nav_item("##nav.for-you", "For you", GC_ICON_AT, page == 5, gc_int_field(frame.nav, 1), page == 5, false)) action = 15;
  place(); if (gc_nav_item("##nav.saved", "Saved", GC_ICON_BOOKMARK, page == 6, 0, false, false)) action = 16;
  draw->AddLine(ImVec2(origin.x + 20.0f, origin.y + y + 8.0f), ImVec2(origin.x + 212.0f, origin.y + y + 8.0f), GC_BORDER, 1.0f);
  y += 18.0f;
  place(); if (gc_nav_item("##nav.repositories", "Repositories", GC_ICON_REPO, page == 1, gc_int_field(frame.nav, 2), false, true)) action = 11;
  place(); if (gc_nav_item("##nav.settings", "Settings", GC_ICON_GEAR, page == 4, 0, false, false)) action = 14;
  ImGui::EndChild();
  return action;
}

// ---------------------------------------------------------------------------
// Activity list pieces

static void gc_skeleton_rows(ImDrawList* draw, ImVec2 origin, float width, int count) {
  for (int k = 0; k < count; ++k) {
    const float y = origin.y + k * 60.0f;
    draw->AddCircleFilled(ImVec2(origin.x + 32.0f, y + 30.0f), 8.0f, GC_HOVER);
    draw->AddRectFilled(ImVec2(origin.x + 52.0f, y + 18.0f), ImVec2(origin.x + 52.0f + width * (0.45f + 0.08f * (k % 3)), y + 30.0f), GC_HOVER, 4.0f);
    draw->AddRectFilled(ImVec2(origin.x + 52.0f, y + 37.0f), ImVec2(origin.x + 52.0f + width * 0.22f, y + 46.0f), GC_HOVER, 4.0f);
    draw->AddRectFilled(ImVec2(origin.x + width - 170.0f, y + 16.0f), ImVec2(origin.x + width - 24.0f, y + 44.0f), GC_HOVER, 6.0f);
    draw->AddLine(ImVec2(origin.x, y + 60.0f), ImVec2(origin.x + width, y + 60.0f), GC_BORDER_MUTED);
  }
}

// Banners above the list. Returns an action and stages the banner key.
static int gc_render_banners(const std::vector<std::vector<std::string>>& banners, float x, float width) {
  int action = 0;
  for (size_t index = 0; index < banners.size(); ++index) {
    const std::vector<std::string>& b = banners[index];
    const std::string kind = gc_field(b, 0);
    const std::string key = gc_field(b, 1);
    const std::string title = gc_field(b, 2);
    const std::string body = gc_field(b, 3);
    const std::string action_label = gc_field(b, 4);
    ImU32 fg = GC_ACCENT, bg = GC_ACCENT_SUBTLE, border = GC_ACCENT_BORDER;
    GcIcon icon = GC_ICON_INFO;
    if (kind == "danger") { fg = GC_DANGER; bg = GC_DANGER_SUBTLE; border = GC_DANGER_BORDER; icon = GC_ICON_ERROR; }
    else if (kind == "warning") { fg = GC_ATTENTION; bg = GC_ATTENTION_SUBTLE; border = GC_ATTENTION_BORDER; icon = GC_ICON_WARNING; }
    const float action_w = action_label.empty() ? 0.0f : gc_button_width(action_label.c_str(), GC_ICON_NONE) + 8.0f;
    const float text_w = width - 40.0f - action_w - 44.0f;
    const float title_h = gc_font_bold->CalcTextSizeA(gc_fs(gc_font_bold, 13.0f), FLT_MAX, text_w, title.c_str()).y;
    const float body_h = body.empty() ? 0.0f : gc_font_regular->CalcTextSizeA(13.0f, FLT_MAX, text_w, body.c_str()).y;
    const float h = ImMax(48.0f, title_h + body_h + 24.0f);
    ImGui::SetCursorPosX(x);
    const ImVec2 pos = ImGui::GetCursorScreenPos();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + h), bg, 8.0f);
    draw->AddRect(pos, ImVec2(pos.x + width, pos.y + h), border, 8.0f);
    gc_icon(draw, icon, ImVec2(pos.x + 14.0f, pos.y + 14.0f), 16.0f, fg);
    draw->AddText(gc_font_bold, gc_fs(gc_font_bold, 13.0f), ImVec2(pos.x + 40.0f, pos.y + 12.0f), GC_FG, title.c_str(), nullptr, text_w);
    if (!body.empty()) {
      draw->AddText(gc_font_regular, 13.0f, ImVec2(pos.x + 40.0f, pos.y + 12.0f + title_h + 2.0f), GC_FG, body.c_str(), nullptr, text_w);
    }
    ImGui::PushID(static_cast<int>(index));
    if (!action_label.empty()) {
      ImGui::SetCursorScreenPos(ImVec2(pos.x + width - 40.0f - action_w + 4.0f, pos.y + (h - 32.0f) * 0.5f));
      if (gc_button("##banner.action", action_label.c_str(), GC_BUTTON_PLAIN)) { gc_selected_key = key; action = 28; }
    }
    ImGui::SetCursorScreenPos(ImVec2(pos.x + width - 38.0f, pos.y + (h - 32.0f) * 0.5f));
    if (gc_icon_button("##banner.dismiss", GC_ICON_CLOSE, GC_MUTED)) { gc_selected_key = key; action = 29; }
    ImGui::PopID();
    ImGui::SetCursorScreenPos(ImVec2(pos.x, pos.y + h + 8.0f));
  }
  return action;
}

// One activity row: I url repo number kind draft title author date updated_at
// read saved reasons nested show_repo fresh_age
static int gc_render_item(const std::vector<std::string>& r, float width) {
  int action = 0;
  const std::string url = gc_field(r, 1);
  const std::string repository = gc_field(r, 2);
  const std::string number = gc_field(r, 3);
  const std::string kind = gc_field(r, 4);
  const bool draft = gc_field(r, 5) == "1";
  const std::string title = gc_field(r, 6);
  const std::string author = gc_field(r, 7);
  const std::string date = gc_field(r, 8);
  const std::string updated_at = gc_field(r, 9);
  const bool read = gc_field(r, 10) == "1";
  const bool saved = gc_field(r, 11) == "1";
  const std::string reasons_text = gc_field(r, 12);
  const bool nested = gc_field(r, 13) == "1";
  const bool show_repository = gc_field(r, 14) == "1";
  const float fresh_age = static_cast<float>(std::atof(gc_field(r, 15).c_str()));
  const float h = 60.0f;
  ImGui::PushID(url.c_str());
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  const bool hovered = ImGui::IsWindowHovered() && ImGui::IsMouseHoveringRect(pos, ImVec2(pos.x + width, pos.y + h));
  // Fresh rows keep a blue tint for 1.5 s, then fade out over 0.6 s.
  if (fresh_age >= 0.0f && fresh_age < 2.1f) {
    const float alpha = fresh_age < 1.5f ? 1.0f : 1.0f - (fresh_age - 1.5f) / 0.6f;
    draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + h), gc_alpha(GC_ACCENT_SUBTLE, alpha));
  } else if (hovered) {
    draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + h), GC_CANVAS);
  }
  draw->AddLine(ImVec2(pos.x, pos.y + h - 1.0f), ImVec2(pos.x + width, pos.y + h - 1.0f), GC_BORDER_MUTED);
  float x = pos.x + 20.0f + (nested ? 32.0f : 0.0f);
  if (!read) draw->AddCircleFilled(ImVec2(x + 4.0f, pos.y + h * 0.5f), 4.0f, GC_ACCENT);
  x += 16.0f;
  if (!nested) {
    const GcIcon icon = kind == "pr" ? (draft ? GC_ICON_PR_DRAFT : GC_ICON_PR) : GC_ICON_ISSUE;
    const ImU32 icon_color = read ? GC_SUBTLE : (draft ? GC_MUTED : GC_SUCCESS);
    gc_icon(draw, icon, ImVec2(x, pos.y + 12.0f), 16.0f, icon_color);
    x += 28.0f;
  }
  const float open_w = gc_button_width("Open", GC_ICON_NONE);
  const char* done_label = read ? "Move to inbox" : "Done";
  const GcIcon done_icon = read ? GC_ICON_INBOX : GC_ICON_CHECK;
  const float done_w = gc_button_width(done_label, done_icon);
  const float actions_w = nested ? open_w + 6.0f + done_w : open_w + 6.0f + done_w + 6.0f + 32.0f + 2.0f + 32.0f;
  const float actions_x = pos.x + width - 20.0f - actions_w;
  const float text_max = actions_x - 16.0f;
  gc_text_ellipsis(read ? gc_font_regular : gc_font_bold, GC_BODY, ImVec2(x, pos.y + 10.0f), text_max, read ? GC_MUTED : GC_FG, title);
  // Meta line: reasons, repository, #number, author, date, state labels.
  float mx = x;
  const float my = pos.y + 34.0f;
  ImGui::PushClipRect(ImVec2(x, my - 4.0f), ImVec2(text_max, my + 22.0f), true);
  if (!reasons_text.empty()) {
    for (const std::string& reason : gc_split(reasons_text, ',')) {
      ImU32 fg, bg, border;
      gc_reason_colors(reason, read, &fg, &bg, &border);
      mx += gc_pill(draw, ImVec2(mx, my - 3.0f), reason, fg, bg, border) + 6.0f;
    }
  }
  if (show_repository) {
    gc_text(draw, gc_font_regular, GC_SMALL, ImVec2(mx, my), GC_MUTED, repository);
    mx += gc_text_size(gc_font_regular, GC_SMALL, repository).x + 8.0f;
  }
  const std::string number_text = "#" + number;
  gc_text(draw, gc_font_mono, 12.0f, ImVec2(mx, my + 0.5f), GC_MUTED, number_text);
  mx += gc_text_size(gc_font_mono, 12.0f, number_text).x;
  std::string after = "  \xC2\xB7  @" + author;
  if (!date.empty()) after += "  \xC2\xB7  updated " + date;
  gc_text(draw, gc_font_regular, GC_SMALL, ImVec2(mx, my), GC_MUTED, after);
  mx += gc_text_size(gc_font_regular, GC_SMALL, after).x + 8.0f;
  if (read) mx += gc_pill(draw, ImVec2(mx, my - 3.0f), "Done", GC_MUTED, GC_WHITE, GC_BORDER) + 6.0f;
  if (draft) mx += gc_pill(draw, ImVec2(mx, my - 3.0f), "Draft", GC_MUTED, GC_WHITE, GC_BORDER) + 6.0f;
  if (saved) mx += gc_pill(draw, ImVec2(mx, my - 3.0f), "Saved", GC_ACCENT, GC_ACCENT_SUBTLE, GC_ACCENT_BORDER) + 6.0f;
  ImGui::PopClipRect();
  const float by = pos.y + (h - 32.0f) * 0.5f;
  ImGui::SetCursorScreenPos(ImVec2(actions_x, by));
  if (gc_button("##activity.open", "Open", GC_BUTTON_DEFAULT)) { gc_selected_url = url; action = 4; }
  ImGui::SetCursorScreenPos(ImVec2(actions_x + open_w + 6.0f, by));
  if (gc_button("##activity.done", done_label, GC_BUTTON_DEFAULT, done_icon)) { gc_selected_url = url; gc_selected_updated_at = updated_at; action = 6; }
  if (!nested) {
    const float sx = actions_x + open_w + 6.0f + done_w + 6.0f;
    ImGui::SetCursorScreenPos(ImVec2(sx, by));
    if (gc_icon_button("##activity.save", saved ? GC_ICON_BOOKMARK_FILLED : GC_ICON_BOOKMARK, saved ? GC_ACCENT : GC_MUTED)) { gc_selected_url = url; action = 22; }
    if (ImGui::IsItemHovered()) ImGui::SetTooltip(saved ? "Remove from Saved" : "Save for later");
    ImGui::SetCursorScreenPos(ImVec2(sx + 34.0f, by));
    if (gc_icon_button("##activity.more", GC_ICON_KEBAB, GC_MUTED)) {
      gc_menu_url = url; gc_menu_repository = repository;
      gc_menu_anchor = ImVec2(sx + 66.0f, by + 36.0f); gc_menu_request = true;
    }
    if (ImGui::IsItemHovered()) ImGui::SetTooltip("More actions");
  }
  ImGui::SetCursorScreenPos(ImVec2(pos.x, pos.y + h));
  ImGui::PopID();
  return action;
}

// B key repo author count summary expanded unread
static int gc_render_bundle(const std::vector<std::string>& r, float width) {
  int action = 0;
  const std::string key = gc_field(r, 1);
  const std::string author = gc_field(r, 3);
  const int count = gc_int_field(r, 4);
  const std::string summary = gc_field(r, 5);
  const bool expanded = gc_field(r, 6) == "1";
  const int unread = gc_int_field(r, 7);
  const float h = 60.0f;
  ImGui::PushID(key.c_str());
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + h), IM_COL32(251, 252, 253, 255));
  draw->AddLine(ImVec2(pos.x, pos.y + h - 1.0f), ImVec2(pos.x + width, pos.y + h - 1.0f), GC_BORDER_MUTED);
  float x = pos.x + 20.0f;
  if (unread > 0) draw->AddCircleFilled(ImVec2(x + 4.0f, pos.y + h * 0.5f), 4.0f, GC_ACCENT);
  x += 16.0f;
  gc_icon(draw, GC_ICON_BUNDLE, ImVec2(x, pos.y + 12.0f), 16.0f, GC_MUTED);
  x += 28.0f;
  char toggle[32];
  if (expanded) std::snprintf(toggle, sizeof(toggle), "Hide");
  else std::snprintf(toggle, sizeof(toggle), "Show %d", count);
  const GcIcon toggle_icon = expanded ? GC_ICON_CHEVRON_UP : GC_ICON_CHEVRON_DOWN;
  const float toggle_w = gc_button_width(toggle, toggle_icon);
  const float done_w = gc_button_width("Done all", GC_ICON_CHECK);
  const float actions_x = pos.x + width - 20.0f - (toggle_w + 6.0f + done_w);
  char title[160];
  std::snprintf(title, sizeof(title), "%d dependency updates from @%s", count, author.c_str());
  gc_text_ellipsis(unread > 0 ? gc_font_bold : gc_font_regular, GC_BODY, ImVec2(x, pos.y + 10.0f), actions_x - 16.0f, unread > 0 ? GC_FG : GC_MUTED, title);
  gc_text_ellipsis(gc_font_regular, GC_SMALL, ImVec2(x, pos.y + 34.0f), actions_x - 16.0f, GC_MUTED, summary);
  const float by = pos.y + (h - 32.0f) * 0.5f;
  ImGui::SetCursorScreenPos(ImVec2(actions_x, by));
  if (gc_button("##bundle.toggle", toggle, GC_BUTTON_DEFAULT, toggle_icon)) { gc_selected_key = key; action = 24; }
  ImGui::SetCursorScreenPos(ImVec2(actions_x + toggle_w + 6.0f, by));
  if (gc_button("##bundle.done", "Done all", GC_BUTTON_DEFAULT, GC_ICON_CHECK, unread == 0)) { gc_selected_key = key; action = 25; }
  ImGui::SetCursorScreenPos(ImVec2(pos.x, pos.y + h));
  ImGui::PopID();
  return action;
}

static void gc_render_group(const std::vector<std::string>& r, float width) {
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + 40.0f), GC_CANVAS);
  draw->AddLine(ImVec2(pos.x, pos.y + 39.0f), ImVec2(pos.x + width, pos.y + 39.0f), GC_BORDER_MUTED);
  gc_icon(draw, GC_ICON_REPO, ImVec2(pos.x + 20.0f, pos.y + 12.0f), 16.0f, GC_MUTED);
  gc_text(draw, gc_font_bold, 13.0f, ImVec2(pos.x + 44.0f, pos.y + 12.0f), GC_FG, gc_field(r, 1));
  ImGui::Dummy(ImVec2(width, 40.0f));
}

static ImVec2 gc_empty_state(float width, GcIcon icon, ImU32 icon_color, const std::string& title, const std::string& body) {
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  const float cx = pos.x + width * 0.5f;
  gc_icon(draw, icon, ImVec2(cx - 16.0f, pos.y + 48.0f), 32.0f, icon_color);
  const float tw = gc_text_size(gc_font_bold, 16.0f, title).x;
  gc_text(draw, gc_font_bold, 16.0f, ImVec2(cx - tw * 0.5f, pos.y + 92.0f), GC_FG, title);
  const float bw = gc_text_size(gc_font_regular, 13.0f, body).x;
  gc_text(draw, gc_font_regular, 13.0f, ImVec2(cx - bw * 0.5f, pos.y + 118.0f), GC_MUTED, body);
  ImGui::Dummy(ImVec2(width, 196.0f));
  return ImVec2(cx, pos.y + 150.0f);
}

static bool gc_segment(const char* id, const char* label, bool selected) {
  const float w = gc_text_size(gc_font_bold, 13.0f, label).x + 28.0f;
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  const bool pressed = ImGui::InvisibleButton(id, ImVec2(w, 28.0f));
  ImDrawList* draw = ImGui::GetWindowDrawList();
  if (selected) {
    draw->AddRectFilled(pos, ImVec2(pos.x + w, pos.y + 28.0f), GC_WHITE, 6.0f);
    draw->AddRect(pos, ImVec2(pos.x + w, pos.y + 28.0f), GC_BORDER, 6.0f);
  } else if (ImGui::IsItemHovered()) {
    draw->AddRectFilled(pos, ImVec2(pos.x + w, pos.y + 28.0f), GC_HOVER, 6.0f);
  }
  ImFont* font = selected ? gc_font_bold : gc_font_regular;
  const float tw = gc_text_size(font, 13.0f, label).x;
  gc_text(draw, font, 13.0f, ImVec2(pos.x + (w - tw) * 0.5f, pos.y + 6.0f), selected ? GC_FG : GC_MUTED, label);
  return pressed;
}

static bool gc_chip(const char* id, const char* label, bool selected, ImU32 dot) {
  const float w = gc_text_size(gc_font_bold, 13.0f, label).x + 24.0f + (dot ? 14.0f : 0.0f);
  const ImVec2 pos = ImGui::GetCursorScreenPos();
  const bool pressed = ImGui::InvisibleButton(id, ImVec2(w, 32.0f));
  const bool hovered = ImGui::IsItemHovered();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  draw->AddRectFilled(pos, ImVec2(pos.x + w, pos.y + 32.0f), selected ? GC_ACCENT_SUBTLE : hovered ? GC_CANVAS : GC_WHITE, 16.0f);
  draw->AddRect(pos, ImVec2(pos.x + w, pos.y + 32.0f), selected ? GC_ACCENT_BORDER : GC_BORDER, 16.0f);
  float x = pos.x + 12.0f;
  if (dot) { draw->AddCircleFilled(ImVec2(x + 4.0f, pos.y + 16.0f), 4.0f, dot); x += 14.0f; }
  gc_text(draw, selected ? gc_font_bold : gc_font_regular, 13.0f, ImVec2(x, pos.y + 8.0f), selected ? GC_ACCENT_EMPHASIS : GC_FG, label);
  return pressed;
}

static bool gc_filters_active(int page) {
  if (page == 5) return !gc_view_reason.empty();
  return gc_view_kind != 0 || !gc_view_repository.empty() || gc_query_input[0] != '\0';
}

static void gc_clear_filters() {
  gc_view_kind = 0; gc_view_repository.clear(); gc_query_input[0] = '\0'; gc_view_reason.clear();
}

// Toolbar for Inbox (kind, repository, query) and For you (reason chips).
static void gc_render_toolbar(const GcFrame& frame, float x, float width) {
  const float row_y = ImGui::GetCursorPosY();
  ImGui::SetCursorPos(ImVec2(x, row_y));
  if (frame.page == 0) {
    const ImVec2 group = ImGui::GetCursorScreenPos();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    const char* labels[] = {"All", "Pull requests", "Issues"};
    float gw = 4.0f;
    for (int k = 0; k < 3; ++k) gw += gc_text_size(gc_font_bold, 13.0f, labels[k]).x + 28.0f + 2.0f;
    gw -= 2.0f;
    draw->AddRectFilled(group, ImVec2(group.x + gw, group.y + 32.0f), GC_CANVAS, 8.0f);
    draw->AddRect(group, ImVec2(group.x + gw, group.y + 32.0f), GC_BORDER, 8.0f);
    float sx = group.x + 2.0f;
    for (int k = 0; k < 3; ++k) {
      ImGui::SetCursorScreenPos(ImVec2(sx, group.y + 2.0f));
      ImGui::PushID(k);
      if (gc_segment("##kind", labels[k], gc_view_kind == k)) gc_view_kind = k;
      ImGui::PopID();
      sx += gc_text_size(gc_font_bold, 13.0f, labels[k]).x + 28.0f + 2.0f;
    }
    ImGui::SetCursorScreenPos(ImVec2(group.x + gw + 16.0f, group.y));
    gc_font(gc_font_regular, 13.0f);
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("Repository");
    ImGui::SameLine();
    ImGui::SetNextItemWidth(220.0f);
    const std::string preview = gc_view_repository.empty() ? std::string("All watched") : gc_view_repository;
    if (ImGui::BeginCombo("##filter.repository", preview.c_str())) {
      if (ImGui::Selectable("All watched", gc_view_repository.empty())) gc_view_repository.clear();
      for (const auto& repository : frame.repositories) {
        const std::string name = gc_field(repository, 0);
        if (ImGui::Selectable(name.c_str(), gc_view_repository == name)) gc_view_repository = name;
      }
      ImGui::EndCombo();
    }
    ImGui::SameLine(0.0f, 12.0f);
    const float remaining = x + width - ImGui::GetCursorPosX() - 124.0f;
    ImGui::SetNextItemWidth(ImMax(160.0f, remaining));
    ImGui::InputTextWithHint("##filter.query", "Filter by title, #number, or @author", gc_query_input, sizeof(gc_query_input));
    gc_pop_font();
  } else {
    struct Reason { const char* label; ImU32 dot; };
    const Reason reasons[] = {
      {"All", 0}, {"Review requested", GC_ACCENT}, {"Assigned", GC_SUCCESS}, {"Mentioned", GC_DONE}, {"Subscribed", GC_SUBTLE},
    };
    float cx = ImGui::GetCursorScreenPos().x;
    const float cy = ImGui::GetCursorScreenPos().y;
    for (int k = 0; k < 5; ++k) {
      ImGui::SetCursorScreenPos(ImVec2(cx, cy));
      ImGui::PushID(k);
      const bool selected = k == 0 ? gc_view_reason.empty() : gc_view_reason == reasons[k].label;
      if (gc_chip("##reason", reasons[k].label, selected, reasons[k].dot)) gc_view_reason = k == 0 ? "" : reasons[k].label;
      ImGui::PopID();
      cx += gc_text_size(gc_font_bold, 13.0f, reasons[k].label).x + 24.0f + (reasons[k].dot ? 14.0f : 0.0f) + 8.0f;
    }
  }
  ImGui::SetCursorPos(ImVec2(x + width - 108.0f, row_y + 5.0f));
  gc_font(gc_font_regular, 13.0f);
  ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(3.0f, 3.0f));
  ImGui::Checkbox("Show done##filter.show-done", &gc_show_done);
  ImGui::PopStyleVar();
  gc_pop_font();
  ImGui::SetCursorPos(ImVec2(0.0f, row_y + 46.0f));
}

static int gc_render_onboarding(float width) {
  int action = 0;
  const float card_w = ImMin(640.0f, width - 48.0f);
  const float x = (width - card_w) * 0.5f;
  ImGui::SetCursorPos(ImVec2(x, 40.0f));
  ImDrawList* draw = ImGui::GetWindowDrawList();
  ImVec2 pos = ImGui::GetCursorScreenPos();
  gc_text(draw, gc_font_bold, 26.0f, pos, GC_FG, "Set up your inbox");
  gc_text(draw, gc_font_regular, GC_BODY, ImVec2(pos.x, pos.y + 38.0f), GC_MUTED, "Two steps: connect GitHub, then choose the repositories you want to follow.");
  pos.y += 76.0f;
  draw->AddRectFilled(pos, ImVec2(pos.x + card_w, pos.y + 228.0f), GC_WHITE, 12.0f);
  draw->AddRect(pos, ImVec2(pos.x + card_w, pos.y + 228.0f), GC_BORDER, 12.0f);
  draw->AddCircleFilled(ImVec2(pos.x + 40.0f, pos.y + 36.0f), 16.0f, GC_ACCENT);
  gc_text(draw, gc_font_bold, GC_BODY, ImVec2(pos.x + 36.0f, pos.y + 27.0f), GC_WHITE, "1");
  gc_text(draw, gc_font_bold, 16.0f, ImVec2(pos.x + 72.0f, pos.y + 20.0f), GC_FG, "Connect GitHub with a personal access token");
  gc_text(draw, gc_font_regular, 13.0f, ImVec2(pos.x + 72.0f, pos.y + 46.0f), GC_MUTED, "Create a fine-grained token with read-only access.");
  gc_text(draw, gc_font_regular, 13.0f, ImVec2(pos.x + 72.0f, pos.y + 64.0f), GC_MUTED, GITHUB_CLIENT_TOKEN_NOTE);
  draw->AddRectFilled(ImVec2(pos.x + 72.0f, pos.y + 92.0f), ImVec2(pos.x + card_w - 24.0f, pos.y + 172.0f), GC_CANVAS, 8.0f);
  const char* permissions[] = {"Issues: Read-only", "Pull requests: Read-only", "Metadata: Read-only"};
  for (int k = 0; k < 3; ++k) {
    gc_icon(draw, GC_ICON_CHECK, ImVec2(pos.x + 86.0f, pos.y + 102.0f + k * 22.0f), 14.0f, GC_SUCCESS);
    gc_text(draw, gc_font_regular, 13.0f, ImVec2(pos.x + 108.0f, pos.y + 101.0f + k * 22.0f), GC_FG, permissions[k]);
  }
  ImGui::SetCursorScreenPos(ImVec2(pos.x + 64.0f, pos.y + 184.0f));
  if (gc_button("##onboarding.create", "Create a token on GitHub", GC_BUTTON_LINK)) {
    gc_selected_url = "https://github.com/settings/personal-access-tokens/new"; action = 4;
  }
  ImGui::SetCursorScreenPos(ImVec2(pos.x + card_w - 24.0f - gc_button_width("Add token", GC_ICON_NONE), pos.y + 20.0f));
  if (gc_button("##onboarding.add-token", "Add token", GC_BUTTON_PRIMARY)) { gc_scope_input[0] = '\0'; action = 1; }
  pos.y += 244.0f;
  draw->AddRectFilled(pos, ImVec2(pos.x + card_w, pos.y + 84.0f), GC_CANVAS, 12.0f);
  draw->AddRect(pos, ImVec2(pos.x + card_w, pos.y + 84.0f), GC_BORDER, 12.0f);
  draw->AddCircleFilled(ImVec2(pos.x + 40.0f, pos.y + 36.0f), 16.0f, GC_HOVER);
  gc_text(draw, gc_font_bold, GC_BODY, ImVec2(pos.x + 36.0f, pos.y + 27.0f), GC_MUTED, "2");
  gc_text(draw, gc_font_bold, 16.0f, ImVec2(pos.x + 72.0f, pos.y + 20.0f), GC_MUTED, "Watch repositories");
  gc_text(draw, gc_font_regular, 13.0f, ImVec2(pos.x + 72.0f, pos.y + 46.0f), GC_MUTED, "After connecting, pick repositories your token can access.");
  ImGui::SetCursorScreenPos(ImVec2(pos.x + card_w - 24.0f - gc_button_width("Choose repositories", GC_ICON_NONE), pos.y + 26.0f));
  gc_button("##onboarding.repositories", "Choose repositories", GC_BUTTON_DEFAULT, GC_ICON_NONE, true);
  ImGui::SetCursorScreenPos(ImVec2(pos.x, pos.y + 100.0f));
  ImGui::Dummy(ImVec2(card_w, 1.0f));
  return action;
}

static int gc_render_activity_page(const GcFrame& frame, float width, double now) {
  int action = 0;
  const float pad = 24.0f;
  if (!frame.has_credentials) return gc_render_onboarding(width);
  if (frame.page == 0 || frame.page == 5) gc_render_toolbar(frame, pad, width - pad * 2.0f);
  {
    const ImVec2 p = ImGui::GetCursorScreenPos();
    ImGui::GetWindowDrawList()->AddLine(ImVec2(ImGui::GetWindowPos().x, p.y), ImVec2(ImGui::GetWindowPos().x + width, p.y), GC_BORDER);
  }
  ImGui::SetCursorPosY(ImGui::GetCursorPosY() + 12.0f);
  if (!frame.banners.empty()) {
    const int banner_action = gc_render_banners(frame.banners, pad, width - pad * 2.0f);
    if (banner_action) action = banner_action;
    ImGui::SetCursorPosY(ImGui::GetCursorPosY() + 4.0f);
  } else {
    ImGui::SetCursorPosY(ImGui::GetCursorPosY() - 12.0f);
  }
  const float list_h = ImGui::GetContentRegionAvail().y;
  ImGui::SetCursorPosX(0.0f);
  ImGui::BeginChild("##activity.list", ImVec2(width, list_h), ImGuiChildFlags_None);
  const float list_w = ImGui::GetContentRegionAvail().x;
  if (frame.busy == 3) {
    const ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    gc_progress_bar(draw, ImVec2(p.x + pad, p.y + 16.0f), ImVec2(p.x + list_w - pad, p.y + 20.0f), frame.progress_done, frame.progress_total, now);
    std::string step = gc_field(frame.loading, 0);
    if (!gc_field(frame.loading, 1).empty()) step += "  \xC2\xB7  " + gc_field(frame.loading, 1);
    if (frame.progress_total > 0) {
      char progress[48];
      std::snprintf(progress, sizeof(progress), "  \xC2\xB7  step %d of %d", ImMin(frame.progress_done + 1, frame.progress_total), frame.progress_total);
      step += progress;
    }
    gc_text(draw, gc_font_regular, 13.0f, ImVec2(p.x + pad, p.y + 30.0f), GC_MUTED, step);
    gc_skeleton_rows(draw, ImVec2(p.x, p.y + 56.0f), list_w, 6);
    ImGui::Dummy(ImVec2(list_w, 420.0f));
  } else if (!gc_field(frame.page_error, 0).empty()) {
    const ImVec2 button = gc_empty_state(list_w, GC_ICON_OFFLINE, GC_MUTED, gc_field(frame.page_error, 0), gc_field(frame.page_error, 1));
    ImGui::SetCursorScreenPos(ImVec2(button.x - gc_button_width("Try again", GC_ICON_NONE) * 0.5f, button.y));
    if (gc_button("##page-error.retry", "Try again", GC_BUTTON_PRIMARY)) { gc_selected_key = "retry"; action = 28; }
  } else if (frame.rows.empty()) {
    if (frame.page != 6 && gc_filters_active(frame.page)) {
      const ImVec2 button = gc_empty_state(list_w, GC_ICON_SEARCH, GC_SUBTLE, "No items match these filters",
        gc_show_done ? "Remove a filter to see more." : "Done items are hidden. Remove a filter or include done items.");
      const float cw = gc_button_width("Clear filters", GC_ICON_NONE);
      const float dw = gc_button_width(gc_show_done ? "Hide done" : "Show done", GC_ICON_NONE);
      ImGui::SetCursorScreenPos(ImVec2(button.x - (cw + 8.0f + dw) * 0.5f, button.y));
      if (gc_button("##empty.clear", "Clear filters", GC_BUTTON_DEFAULT)) gc_clear_filters();
      ImGui::SetCursorScreenPos(ImVec2(button.x - (cw + 8.0f + dw) * 0.5f + cw + 8.0f, button.y));
      if (gc_button("##empty.show-done", gc_show_done ? "Hide done" : "Show done", GC_BUTTON_DEFAULT)) gc_show_done = !gc_show_done;
    } else if (frame.page == 6) {
      gc_empty_state(list_w, GC_ICON_BOOKMARK, GC_SUBTLE, "No saved items yet", "Use the bookmark button on any row in Inbox or For you.");
    } else if (frame.page == 5) {
      gc_empty_state(list_w, GC_ICON_CHECK_CIRCLE, GC_SUCCESS, "Nothing needs you right now", "Review requests, assignments, and mentions will appear here.");
    } else {
      const ImVec2 button = gc_empty_state(list_w, GC_ICON_CHECK_CIRCLE, GC_SUCCESS, "You're all caught up", "New activity from watched repositories will appear here.");
      if (!gc_show_done) {
        ImGui::SetCursorScreenPos(ImVec2(button.x - gc_button_width("Show done", GC_ICON_NONE) * 0.5f, button.y));
        if (gc_button("##empty.show-done-inbox", "Show done", GC_BUTTON_DEFAULT)) gc_show_done = true;
      }
    }
  } else {
    for (const std::vector<std::string>& row : frame.rows) {
      const std::string type = gc_field(row, 0);
      // Rows outside the scrolled viewport only reserve their height, so
      // long lists cost little to draw.
      const float row_h = type == "G" ? 40.0f : 60.0f;
      if (!ImGui::IsRectVisible(ImVec2(list_w, row_h))) {
        // Advance exactly as the drawn row would: group headers end with a
        // Dummy, other rows move the cursor without item spacing.
        if (type == "G") {
          ImGui::Dummy(ImVec2(list_w, row_h));
        } else {
          const ImVec2 p = ImGui::GetCursorScreenPos();
          ImGui::SetCursorScreenPos(ImVec2(p.x, p.y + row_h));
        }
        continue;
      }
      int row_action = 0;
      if (type == "G") gc_render_group(row, list_w);
      else if (type == "B") row_action = gc_render_bundle(row, list_w);
      else row_action = gc_render_item(row, list_w);
      if (row_action) action = row_action;
    }
    ImGui::Dummy(ImVec2(list_w, 80.0f));
  }
  ImGui::EndChild();
  return action;
}

// ---------------------------------------------------------------------------
// Repositories and Settings

static int gc_render_repositories(const GcFrame& frame, float width) {
  int action = 0;
  const float pad = 24.0f;
  const float col_w = (width - pad * 3.0f) * 0.5f;
  const float top = ImGui::GetCursorPosY() + 12.0f;
  ImDrawList* draw = ImGui::GetWindowDrawList();
  // Left column: watch input and watched list.
  ImGui::SetCursorPos(ImVec2(pad, top));
  gc_text(draw, gc_font_bold, GC_BODY, ImGui::GetCursorScreenPos(), GC_FG, "Watch a repository");
  ImGui::SetCursorPos(ImVec2(pad, top + 26.0f));
  gc_font(gc_font_regular, 13.0f);
  ImGui::SetNextItemWidth(col_w - 88.0f);
  const bool submitted = ImGui::InputTextWithHint("##repository.input", "owner/repository", gc_repository_input, sizeof(gc_repository_input), ImGuiInputTextFlags_EnterReturnsTrue);
  gc_pop_font();
  ImGui::SetCursorPos(ImVec2(pad + col_w - 80.0f, top + 26.0f));
  const bool empty_input = gc_repository_input[0] == '\0';
  if (gc_button("##repository.register", "Watch", GC_BUTTON_PRIMARY, GC_ICON_NONE, empty_input, 80.0f) || (submitted && !empty_input)) {
    gc_watch_request = gc_repository_input; action = 2;
  }
  ImGui::SetCursorPos(ImVec2(pad, top + 82.0f));
  char heading[64];
  std::snprintf(heading, sizeof(heading), "Watched \xC2\xB7 %d", static_cast<int>(frame.repositories.size()));
  ImVec2 list = ImGui::GetCursorScreenPos();
  gc_text(draw, gc_font_bold, GC_BODY, list, GC_FG, heading);
  list.y += 28.0f;
  const float row_h = 52.0f;
  const float list_h = ImMax(1.0f, static_cast<float>(frame.repositories.size())) * row_h;
  draw->AddRect(list, ImVec2(list.x + col_w, list.y + list_h), GC_BORDER, 12.0f);
  if (frame.repositories.empty()) {
    gc_text(draw, gc_font_regular, 13.0f, ImVec2(list.x + 20.0f, list.y + 17.0f), GC_MUTED, "No repositories are watched yet.");
  }
  for (size_t k = 0; k < frame.repositories.size(); ++k) {
    const std::string name = gc_field(frame.repositories[k], 0);
    const float y = list.y + k * row_h;
    if (k > 0) draw->AddLine(ImVec2(list.x + 1.0f, y), ImVec2(list.x + col_w - 1.0f, y), GC_BORDER_MUTED);
    gc_icon(draw, GC_ICON_REPO, ImVec2(list.x + 20.0f, y + 18.0f), 16.0f, GC_MUTED);
    gc_text_ellipsis(gc_font_bold, GC_BODY, ImVec2(list.x + 46.0f, y + 16.0f), list.x + col_w - 124.0f, GC_FG, name);
    ImGui::SetCursorScreenPos(ImVec2(list.x + col_w - 16.0f - 88.0f, y + 10.0f));
    ImGui::PushID(name.c_str());
    if (gc_button("##watched.remove", "Unwatch", GC_BUTTON_DANGER, GC_ICON_NONE, false, 88.0f)) { gc_selected_repository = name; action = 5; }
    ImGui::PopID();
  }
  draw->AddText(gc_font_regular, 12.0f, ImVec2(list.x, list.y + list_h + 10.0f), GC_MUTED,
                "Unwatching keeps done and saved state. You can watch the repository again at any time.", nullptr, col_w);
  // Right column: suggestions from every saved token.
  const float rx = pad * 2.0f + col_w;
  ImGui::SetCursorPos(ImVec2(rx, top));
  gc_text(draw, gc_font_bold, GC_BODY, ImGui::GetCursorScreenPos(), GC_FG, "From your accounts");
  ImGui::SetCursorPos(ImVec2(rx, top + 26.0f));
  gc_font(gc_font_regular, 13.0f);
  ImGui::SetNextItemWidth(col_w);
  ImGui::InputTextWithHint("##suggestions.filter", "Filter repositories", gc_suggestion_filter, sizeof(gc_suggestion_filter));
  gc_pop_font();
  ImGui::SetCursorPos(ImVec2(rx, top + 82.0f));
  const float avail_h = ImGui::GetContentRegionAvail().y - 20.0f;
  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 12.0f);
  ImGui::BeginChild("##suggestions", ImVec2(col_w, avail_h), ImGuiChildFlags_Borders);
  ImDrawList* sdraw = ImGui::GetWindowDrawList();
  const float sw = ImGui::GetContentRegionAvail().x;
  int shown = 0;
  for (const auto& suggestion : frame.suggestions) {
    const std::string name = gc_field(suggestion, 0);
    if (gc_suggestion_filter[0] && !gc_contains_ci(name, gc_suggestion_filter)) continue;
    const bool is_private = gc_field(suggestion, 1) == "1";
    const bool archived = gc_field(suggestion, 2) == "1";
    const bool watched = gc_field(suggestion, 3) == "1";
    const int reviews = gc_int_field(suggestion, 4);
    const float h = reviews > 0 ? 64.0f : 52.0f;
    const ImVec2 p = ImGui::GetCursorScreenPos();
    if (reviews > 0) sdraw->AddRectFilled(p, ImVec2(p.x + sw, p.y + h), IM_COL32(246, 251, 255, 255));
    if (shown > 0) sdraw->AddLine(p, ImVec2(p.x + sw, p.y), GC_BORDER_MUTED);
    gc_icon(sdraw, GC_ICON_REPO, ImVec2(p.x + 16.0f, p.y + (reviews > 0 ? 14.0f : 18.0f)), 16.0f, watched ? GC_SUBTLE : GC_MUTED);
    float label_x = p.x + sw - 16.0f - 88.0f - 8.0f;
    if (archived) { label_x -= gc_text_size(gc_font_regular, 12.0f, "Archived").x + 16.0f; gc_pill(sdraw, ImVec2(label_x, p.y + (h - 20.0f) * 0.5f), "Archived", GC_MUTED, GC_WHITE, GC_BORDER); label_x -= 8.0f; }
    else if (is_private) { label_x -= gc_text_size(gc_font_regular, 12.0f, "Private").x + 16.0f; gc_pill(sdraw, ImVec2(label_x, p.y + (h - 20.0f) * 0.5f), "Private", GC_MUTED, GC_WHITE, GC_BORDER); label_x -= 8.0f; }
    gc_text_ellipsis(watched ? gc_font_regular : gc_font_bold, GC_BODY, ImVec2(p.x + 42.0f, p.y + (reviews > 0 ? 12.0f : 16.0f)), label_x, watched ? GC_MUTED : GC_FG, name);
    if (reviews > 0) {
      char text[96];
      std::snprintf(text, sizeof(text), reviews == 1 ? "Has %d review request for you" : "Has %d review requests for you", reviews);
      gc_text(sdraw, gc_font_regular, 12.0f, ImVec2(p.x + 42.0f, p.y + 36.0f), GC_ACCENT, text);
    }
    ImGui::SetCursorScreenPos(ImVec2(p.x + sw - 16.0f - 88.0f, p.y + (h - 32.0f) * 0.5f));
    ImGui::PushID(name.c_str());
    if (watched) {
      gc_button("##suggestion.watched", "Watched", GC_BUTTON_DEFAULT, GC_ICON_NONE, true, 88.0f);
    } else if (gc_button("##suggestion.watch", "Watch", reviews > 0 ? GC_BUTTON_PRIMARY : GC_BUTTON_DEFAULT, GC_ICON_NONE, false, 88.0f)) {
      gc_watch_request = name; action = 2;
    }
    ImGui::PopID();
    ImGui::SetCursorScreenPos(ImVec2(p.x, p.y + h));
    ImGui::Dummy(ImVec2(sw, 0.0f));
    ++shown;
  }
  if (shown == 0) {
    const ImVec2 p = ImGui::GetCursorScreenPos();
    gc_text(sdraw, gc_font_regular, 13.0f, ImVec2(p.x + 16.0f, p.y + 16.0f), GC_MUTED,
            frame.suggestions.empty() ? "No repository suggestions are available for your tokens." : "No repositories match this filter.");
    ImGui::Dummy(ImVec2(sw, 48.0f));
  }
  ImGui::EndChild();
  ImGui::PopStyleVar();
  return action;
}

static void gc_card_frame(ImDrawList* draw, ImVec2 pos, float width, float height, float head, const char* title) {
  draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + head), GC_CANVAS, 12.0f, ImDrawFlags_RoundCornersTop);
  draw->AddRect(pos, ImVec2(pos.x + width, pos.y + height), GC_BORDER, 12.0f);
  draw->AddLine(ImVec2(pos.x, pos.y + head), ImVec2(pos.x + width, pos.y + head), GC_BORDER);
  gc_text(draw, gc_font_bold, GC_BODY, ImVec2(pos.x + 20.0f, pos.y + 14.0f), GC_FG, title);
}

static int gc_render_settings(const GcFrame& frame, float width) {
  int action = 0;
  const float pad = 24.0f;
  const float card_w = ImMin(760.0f, width - pad * 2.0f);
  ImDrawList* draw = ImGui::GetWindowDrawList();
  ImGui::SetCursorPos(ImVec2(pad, ImGui::GetCursorPosY() + 12.0f));
  ImVec2 pos = ImGui::GetCursorScreenPos();
  const float head_h = 64.0f;
  const float row_h = 60.0f;
  const float tokens_h = head_h + ImMax(1.0f, static_cast<float>(frame.credentials.size())) * row_h;
  gc_card_frame(draw, pos, card_w, tokens_h, head_h, "Personal access tokens");
  gc_text(draw, gc_font_regular, 12.0f, ImVec2(pos.x + 20.0f, pos.y + 36.0f), GC_MUTED, GITHUB_CLIENT_TOKEN_NOTE " Owner tokens are used for that owner's repositories.");
  ImGui::SetCursorScreenPos(ImVec2(pos.x + card_w - 20.0f - gc_button_width("Add token", GC_ICON_NONE), pos.y + 16.0f));
  if (gc_button("##auth.sign-in", "Add token", GC_BUTTON_PRIMARY)) { gc_scope_input[0] = '\0'; action = 1; }
  if (frame.credentials.empty()) {
    gc_text(draw, gc_font_regular, 13.0f, ImVec2(pos.x + 20.0f, pos.y + head_h + 20.0f), GC_MUTED, "No token is saved yet.");
  }
  for (size_t k = 0; k < frame.credentials.size(); ++k) {
    const std::string scope = gc_field(frame.credentials[k], 0);
    const std::string login = gc_field(frame.credentials[k], 1);
    const std::string error = gc_field(frame.credentials[k], 2);
    const float y = pos.y + head_h + k * row_h;
    if (k > 0) draw->AddLine(ImVec2(pos.x + 1.0f, y), ImVec2(pos.x + card_w - 1.0f, y), GC_BORDER_MUTED);
    const ImVec2 avatar(pos.x + 36.0f, y + row_h * 0.5f);
    draw->AddCircleFilled(avatar, 16.0f, error.empty() ? GC_HOVER : GC_DANGER_SUBTLE);
    if (error.empty()) {
      const std::string letter(1, static_cast<char>(std::toupper(static_cast<unsigned char>(scope.empty() ? '?' : scope[0]))));
      gc_text(draw, gc_font_bold, 12.0f, ImVec2(avatar.x - gc_text_size(gc_font_bold, 12.0f, letter).x * 0.5f, avatar.y - 7.0f), GC_MUTED, letter);
    } else {
      gc_icon(draw, GC_ICON_LOCK, ImVec2(avatar.x - 8.0f, avatar.y - 8.0f), 16.0f, GC_DANGER);
    }
    const std::string label = scope == "default" ? "Default" : scope;
    gc_text(draw, gc_font_bold, GC_BODY, ImVec2(pos.x + 64.0f, y + 11.0f), GC_FG, label);
    if (scope == "default") {
      gc_pill(draw, ImVec2(pos.x + 72.0f + gc_text_size(gc_font_bold, GC_BODY, label).x, y + 10.0f), "All other repositories", GC_MUTED, GC_WHITE, GC_BORDER);
    }
    const float buttons_x = pos.x + card_w - 20.0f - 88.0f - (error.empty() ? 0.0f : 96.0f);
    if (error.empty()) {
      gc_text(draw, gc_font_regular, 12.0f, ImVec2(pos.x + 64.0f, y + 34.0f), GC_MUTED, login.empty() ? std::string("Not verified yet") : ("Signed in as @" + login));
    } else {
      gc_text_ellipsis(gc_font_regular, 12.0f, ImVec2(pos.x + 64.0f, y + 34.0f), buttons_x - 12.0f, GC_DANGER, error);
    }
    ImGui::PushID(scope.c_str());
    if (!error.empty()) {
      ImGui::SetCursorScreenPos(ImVec2(buttons_x, y + 14.0f));
      if (gc_button("##credential.replace", "Replace", GC_BUTTON_DEFAULT, GC_ICON_NONE, false, 88.0f)) {
        std::snprintf(gc_scope_input, sizeof(gc_scope_input), "%s", scope == "default" ? "" : scope.c_str());
        action = 1;
      }
    }
    ImGui::SetCursorScreenPos(ImVec2(pos.x + card_w - 20.0f - 88.0f, y + 14.0f));
    if (gc_button("##credential.remove", "Remove", GC_BUTTON_DANGER, GC_ICON_NONE, false, 88.0f)) { gc_confirm_scope = scope; gc_confirm_request = true; }
    ImGui::PopID();
  }
  pos.y += tokens_h + 20.0f;
  const float sync_h = 124.0f;
  gc_card_frame(draw, pos, card_w, sync_h, 48.0f, "Sync");
  ImGui::SetCursorScreenPos(ImVec2(pos.x + 16.0f, pos.y + 62.0f));
  gc_font(gc_font_bold, GC_BODY);
  ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(3.0f, 3.0f));
  ImGui::Checkbox("Auto refresh every 5 minutes##settings.auto-refresh", &gc_auto_refresh_enabled);
  ImGui::PopStyleVar();
  gc_pop_font();
  gc_text(draw, gc_font_regular, 12.0f, ImVec2(pos.x + 46.0f, pos.y + 90.0f), GC_MUTED,
          "Refreshes in the background without blocking the window. New or updated items post a notification.");
  pos.y += sync_h + 20.0f;
  const float data_h = 104.0f;
  gc_card_frame(draw, pos, card_w, data_h, 48.0f, "Local data");
  gc_text(draw, gc_font_regular, 13.0f, ImVec2(pos.x + 20.0f, pos.y + 58.0f), GC_MUTED, "Watched repositories, done state, and saved items are stored in");
  gc_text(draw, gc_font_mono, 12.0f, ImVec2(pos.x + 20.0f, pos.y + 78.0f), GC_FG, gc_field(frame.nav, 4));
  ImGui::SetCursorScreenPos(ImVec2(pos.x, pos.y + data_h + 16.0f));
  ImGui::Dummy(ImVec2(card_w, 1.0f));
  return action;
}

// ---------------------------------------------------------------------------
// Overlays

static int gc_render_row_menu() {
  int action = 0;
  if (gc_menu_request) { ImGui::OpenPopup("##row.menu"); gc_menu_request = false; }
  ImGui::SetNextWindowPos(gc_menu_anchor, ImGuiCond_Appearing, ImVec2(1.0f, 0.0f));
  ImGui::SetNextWindowSize(ImVec2(284.0f, 0.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(8.0f, 8.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(0.0f, 2.0f));
  if (ImGui::BeginPopup("##row.menu")) {
    auto item = [&](const char* id, GcIcon icon, const char* label, const char* detail, ImU32 color) {
      const ImVec2 pos = ImGui::GetCursorScreenPos();
      const float w = 268.0f;
      const float h = detail ? 52.0f : 36.0f;
      const bool pressed = ImGui::InvisibleButton(id, ImVec2(w, h));
      ImDrawList* draw = ImGui::GetWindowDrawList();
      if (ImGui::IsItemHovered()) draw->AddRectFilled(pos, ImVec2(pos.x + w, pos.y + h), GC_CANVAS, 6.0f);
      gc_icon(draw, icon, ImVec2(pos.x + 12.0f, pos.y + 10.0f), 16.0f, color == GC_FG ? GC_MUTED : color);
      gc_text(draw, detail ? gc_font_bold : gc_font_regular, 13.0f, ImVec2(pos.x + 38.0f, pos.y + 10.0f), color, label);
      if (detail) gc_text(draw, gc_font_regular, 12.0f, ImVec2(pos.x + 38.0f, pos.y + 29.0f), GC_MUTED, detail);
      return pressed;
    };
    if (item("##menu.copy", GC_ICON_LINK, "Copy link", nullptr, GC_FG)) {
      ImGui::SetClipboardText(gc_menu_url.c_str()); action = 31; ImGui::CloseCurrentPopup();
    }
    if (item("##menu.only-repository", GC_ICON_REPO, "Show only this repository", nullptr, GC_FG)) {
      gc_view_repository = gc_menu_repository; action = 10; ImGui::CloseCurrentPopup();
    }
    const ImVec2 sep = ImGui::GetCursorScreenPos();
    ImGui::GetWindowDrawList()->AddLine(ImVec2(sep.x, sep.y + 3.0f), ImVec2(sep.x + 268.0f, sep.y + 3.0f), GC_BORDER_MUTED);
    ImGui::Dummy(ImVec2(268.0f, 6.0f));
    if (item("##menu.unsubscribe", GC_ICON_BELL_OFF, "Unsubscribe", "Hide this item everywhere and stop notifications", GC_DANGER_BUTTON)) {
      gc_selected_url = gc_menu_url; action = 23; ImGui::CloseCurrentPopup();
    }
    ImGui::EndPopup();
  }
  ImGui::PopStyleVar(2);
  return action;
}

static void gc_dialog_begin_style() {
  ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 20.0f);
  ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(24.0f, 24.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(8.0f, 8.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
}

static void gc_dialog_end_style() { ImGui::PopStyleVar(4); }

static void gc_center_next_window(float width) {
  ImGuiIO& io = ImGui::GetIO();
  ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x * 0.5f, io.DisplaySize.y * 0.5f), ImGuiCond_Always, ImVec2(0.5f, 0.5f));
  ImGui::SetNextWindowSize(ImVec2(width, 0.0f));
}

static void gc_label(const char* text) {
  gc_font(gc_font_bold, 13.0f);
  ImGui::TextUnformatted(text);
  gc_pop_font();
}

static void gc_hint(const std::string& text, ImU32 color = GC_MUTED) {
  gc_font(gc_font_regular, 12.0f);
  ImGui::PushStyleColor(ImGuiCol_Text, color);
  ImGui::PushTextWrapPos(0.0f);
  ImGui::TextUnformatted(text.c_str());
  ImGui::PopTextWrapPos();
  ImGui::PopStyleColor();
  gc_pop_font();
}

static const ImGuiWindowFlags GC_DIALOG_FLAGS =
  ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings;

// token: state field message open_seq close_seq. state 1 = verifying, 2 = error.
static int gc_render_token_dialog(const GcFrame& frame, double now) {
  int action = 0;
  const int state = gc_int_field(frame.token, 0);
  const int field = gc_int_field(frame.token, 1);
  const std::string message = gc_field(frame.token, 2);
  const int open_seq = gc_int_field(frame.token, 3);
  const int close_seq = gc_int_field(frame.token, 4);
  const char* id = "Add personal access token##auth.pat-dialog";
  if (open_seq != gc_token_open_seen) {
    gc_token_open_seen = open_seq;
    // Field 5 pre-fills the owner: "-" clears it, empty keeps it.
    const std::string prefill = gc_field(frame.token, 5);
    if (prefill == "-") gc_scope_input[0] = '\0';
    else if (!prefill.empty()) std::snprintf(gc_scope_input, sizeof(gc_scope_input), "%s", prefill.c_str());
    if (open_seq > 0) { gc_token_input[0] = '\0'; ImGui::OpenPopup(id); }
  }
  gc_dialog_begin_style();
  gc_center_next_window(460.0f);
  if (ImGui::BeginPopupModal(id, nullptr, GC_DIALOG_FLAGS)) {
    if (close_seq != gc_token_close_seen) {
      gc_token_close_seen = close_seq;
      gc_scope_input[0] = '\0';
      gc_token_input[0] = '\0';
      ImGui::CloseCurrentPopup();
    }
    const bool verifying = state == 1;
    gc_font(gc_font_bold, 16.0f);
    ImGui::TextUnformatted("Add personal access token");
    gc_pop_font();
    ImGui::Dummy(ImVec2(1.0f, 4.0f));
    gc_font(gc_font_regular, 13.0f);
    ImGui::BeginDisabled(verifying);
    gc_label("Owner or organization");
    const bool owner_error = state == 2 && field == 0;
    if (owner_error) ImGui::PushStyleColor(ImGuiCol_Border, GC_DANGER_BUTTON);
    ImGui::SetNextItemWidth(-1.0f);
    ImGui::InputTextWithHint("##auth.scope-input", "Leave empty for the default token", gc_scope_input, sizeof(gc_scope_input));
    if (owner_error) ImGui::PopStyleColor();
    if (owner_error) gc_hint(message, GC_DANGER);
    else gc_hint("Owner tokens are used for that owner's repositories. The default token covers everything else.");
    ImGui::Dummy(ImVec2(1.0f, 4.0f));
    gc_label("Token");
    const bool token_error = state == 2 && field == 1;
    if (token_error) ImGui::PushStyleColor(ImGuiCol_Border, GC_DANGER_BUTTON);
    ImGui::SetNextItemWidth(-1.0f);
    ImGui::InputTextWithHint("##auth.pat-input", "github_pat_...", gc_token_input, sizeof(gc_token_input), ImGuiInputTextFlags_Password);
    if (token_error) ImGui::PopStyleColor();
    if (token_error) gc_hint(message, GC_DANGER);
    else gc_hint("Needs read-only access to issues, pull requests, and metadata. " GITHUB_CLIENT_TOKEN_NOTE);
    ImGui::EndDisabled();
    ImGui::SetCursorPosX(ImGui::GetCursorPosX() - 8.0f);
    if (gc_button("##auth.create-link", "Create a token on GitHub", GC_BUTTON_LINK, GC_ICON_NONE, false, 0.0f, 26.0f)) {
      gc_selected_url = "https://github.com/settings/personal-access-tokens/new"; action = 4;
    }
    gc_pop_font();
    ImGui::Dummy(ImVec2(1.0f, 6.0f));
    const char* save_label = verifying ? "      Verifying with GitHub" : "Save securely";
    const float save_w = gc_button_width(save_label, GC_ICON_NONE);
    const float cancel_w = gc_button_width("Cancel", GC_ICON_NONE);
    ImGui::SetCursorPosX(ImGui::GetWindowWidth() - 24.0f - save_w - 8.0f - cancel_w);
    const float row_y = ImGui::GetCursorPosY();
    if (gc_button("##auth.pat-cancel", "Cancel", GC_BUTTON_DEFAULT)) {
      gc_scope_input[0] = '\0'; gc_token_input[0] = '\0'; action = 30; ImGui::CloseCurrentPopup();
    }
    ImGui::SetCursorPos(ImVec2(ImGui::GetWindowWidth() - 24.0f - save_w, row_y));
    const ImVec2 save_pos = ImGui::GetCursorScreenPos();
    if (gc_button("##auth.pat-save", save_label, GC_BUTTON_PRIMARY, GC_ICON_NONE, verifying || gc_token_input[0] == '\0', save_w)) action = 3;
    if (verifying) {
      gc_spinner(ImGui::GetWindowDrawList(), ImVec2(save_pos.x + 20.0f, save_pos.y + 16.0f), 6.0f, 2.0f, now, gc_alpha(GC_WHITE, 0.35f), GC_WHITE);
    }
    ImGui::EndPopup();
  }
  gc_dialog_end_style();
  return action;
}

static int gc_render_confirm_remove() {
  int action = 0;
  const char* id = "Remove token##credential.confirm";
  if (gc_confirm_request) { gc_confirm_request = false; ImGui::OpenPopup(id); }
  gc_dialog_begin_style();
  gc_center_next_window(420.0f);
  if (ImGui::BeginPopupModal(id, nullptr, GC_DIALOG_FLAGS)) {
    gc_font(gc_font_bold, 16.0f);
    ImGui::Text("Remove the %s token?", gc_confirm_scope.c_str());
    gc_pop_font();
    gc_font(gc_font_regular, 13.0f);
    ImGui::PushStyleColor(ImGuiCol_Text, GC_MUTED);
    ImGui::TextWrapped("%s", gc_confirm_scope == "default"
      ? "Repositories without an owner token will stop updating. The token is deleted from this computer; you would need to paste it again."
      : "Its repositories will use another saved token that can access them. If none can, they stop updating. The token is deleted from this computer; you would need to paste it again.");
    ImGui::PopStyleColor();
    gc_pop_font();
    ImGui::Dummy(ImVec2(1.0f, 8.0f));
    const float remove_w = gc_button_width("Remove token", GC_ICON_NONE);
    const float cancel_w = gc_button_width("Cancel", GC_ICON_NONE);
    const float row_y = ImGui::GetCursorPosY();
    ImGui::SetCursorPos(ImVec2(ImGui::GetWindowWidth() - 24.0f - remove_w - 8.0f - cancel_w, row_y));
    if (gc_button("##confirm.cancel", "Cancel", GC_BUTTON_DEFAULT)) ImGui::CloseCurrentPopup();
    ImGui::SetCursorPos(ImVec2(ImGui::GetWindowWidth() - 24.0f - remove_w, row_y));
    if (gc_button("##confirm.remove", "Remove token", GC_BUTTON_DANGER_SOLID)) {
      gc_selected_credential = gc_confirm_scope; action = 7; ImGui::CloseCurrentPopup();
    }
    ImGui::EndPopup();
  }
  gc_dialog_end_style();
  return action;
}

// alert: seq title body
static int gc_render_alert(const GcFrame& frame) {
  int action = 0;
  const int seq = gc_int_field(frame.alert, 0);
  const char* id = "Alert##app.alert";
  if (seq != gc_alert_seq_seen) { gc_alert_seq_seen = seq; if (seq > 0) ImGui::OpenPopup(id); }
  gc_dialog_begin_style();
  gc_center_next_window(400.0f);
  if (ImGui::BeginPopupModal(id, nullptr, GC_DIALOG_FLAGS)) {
    gc_font(gc_font_bold, 16.0f);
    ImGui::TextUnformatted(gc_field(frame.alert, 1).c_str());
    gc_pop_font();
    gc_font(gc_font_regular, 13.0f);
    ImGui::PushStyleColor(ImGuiCol_Text, GC_MUTED);
    ImGui::TextWrapped("%s", gc_field(frame.alert, 2).c_str());
    ImGui::PopStyleColor();
    gc_pop_font();
    ImGui::Dummy(ImVec2(1.0f, 8.0f));
    const float retry_w = gc_button_width("Try again", GC_ICON_NONE);
    const float close_w = gc_button_width("Close", GC_ICON_NONE);
    const float row_y = ImGui::GetCursorPosY();
    ImGui::SetCursorPos(ImVec2(ImGui::GetWindowWidth() - 24.0f - retry_w - 8.0f - close_w, row_y));
    if (gc_button("##alert.close", "Close", GC_BUTTON_DEFAULT)) ImGui::CloseCurrentPopup();
    ImGui::SetCursorPos(ImVec2(ImGui::GetWindowWidth() - 24.0f - retry_w, row_y));
    if (gc_button("##alert.retry", "Try again", GC_BUTTON_PRIMARY)) { gc_selected_key = "retry"; action = 28; ImGui::CloseCurrentPopup(); }
    ImGui::EndPopup();
  }
  gc_dialog_end_style();
  return action;
}

// The dialog appears only when a fetch lasts longer than 300 ms and then
// stays for at least 500 ms, so quick fetches do not flash.
static int gc_render_loading_dialog(const GcFrame& frame, double now) {
  int action = 0;
  const bool busy = frame.busy == 2;
  if (busy && gc_modal_busy_since < 0.0) gc_modal_busy_since = now;
  if (!busy) gc_modal_busy_since = -1.0;
  bool want = busy && now - gc_modal_busy_since >= 0.3;
  if (!busy && gc_modal_visible && now - gc_modal_shown_at < 0.5) want = true;
  const char* id = "Loading##loading.dialog";
  if (want && !gc_modal_visible) { gc_modal_visible = true; gc_modal_shown_at = now; ImGui::OpenPopup(id); }
  if (!gc_modal_visible) return 0;
  const float appear = gc_ease_out(static_cast<float>((now - gc_modal_shown_at) / 0.2));
  ImGui::PushStyleColor(ImGuiCol_ModalWindowDimBg, gc_alpha(IM_COL32(31, 35, 40, 82), appear));
  gc_dialog_begin_style();
  gc_center_next_window(360.0f);
  ImGui::PushStyleVar(ImGuiStyleVar_Alpha, 0.001f + 0.999f * appear);
  if (ImGui::BeginPopupModal(id, nullptr, GC_DIALOG_FLAGS)) {
    const float width = ImGui::GetContentRegionAvail().x;
    ImGui::Dummy(ImVec2(width, 44.0f));
    const ImVec2 top = ImGui::GetItemRectMin();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    gc_spinner(draw, ImVec2(top.x + width * 0.5f, top.y + 22.0f), 19.0f, 4.0f, now);
    const std::string title = gc_field(frame.loading, 0);
    const std::string detail = gc_field(frame.loading, 1);
    const ImVec2 p = ImGui::GetCursorScreenPos();
    const float tw = gc_text_size(gc_font_bold, 16.0f, title).x;
    gc_text(draw, gc_font_bold, 16.0f, ImVec2(p.x + (width - tw) * 0.5f, p.y + 4.0f), GC_FG, title);
    std::string detail_line = detail;
    if (frame.progress_total > 0) {
      char progress[64];
      std::snprintf(progress, sizeof(progress), "%d of %d", ImMin(frame.progress_done + 1, frame.progress_total), frame.progress_total);
      detail_line = detail.empty() ? std::string(progress) : detail + "  \xC2\xB7  " + progress;
    }
    const float dw = ImMin(width, gc_text_size(gc_font_regular, 13.0f, detail_line).x);
    gc_text_ellipsis(gc_font_regular, 13.0f, ImVec2(p.x + (width - dw) * 0.5f, p.y + 30.0f), p.x + width, GC_MUTED, detail_line);
    gc_progress_bar(draw, ImVec2(p.x, p.y + 58.0f), ImVec2(p.x + width, p.y + 62.0f), frame.progress_done, frame.progress_total, now);
    if (frame.cancellable) {
      const float cw = gc_button_width("Cancel", GC_ICON_NONE);
      ImGui::SetCursorScreenPos(ImVec2(p.x + (width - cw) * 0.5f, p.y + 76.0f));
      if (gc_button("##loading.cancel", "Cancel", GC_BUTTON_DEFAULT, GC_ICON_NONE, !busy)) action = 27;
    } else {
      ImGui::SetCursorScreenPos(ImVec2(p.x, p.y + 70.0f));
      ImGui::Dummy(ImVec2(width, 1.0f));
    }
    if (!want) { gc_modal_visible = false; ImGui::CloseCurrentPopup(); }
    ImGui::EndPopup();
  } else {
    gc_modal_visible = false;
  }
  ImGui::PopStyleVar();
  gc_dialog_end_style();
  ImGui::PopStyleColor();
  return action;
}

// snackbar: seq message undo. Enters by rising 16 px over 250 ms, stays 5 s.
static int gc_render_snackbar(const GcFrame& frame, ImVec2 panel_min, ImVec2 panel_max, double now) {
  int action = 0;
  const int seq = gc_int_field(frame.snackbar, 0);
  const std::string message = gc_field(frame.snackbar, 1);
  const bool undo = gc_field(frame.snackbar, 2) == "1";
  if (seq != gc_snack_seq_seen) {
    gc_snack_seq_seen = seq;
    if (!message.empty() && seq > 0) { gc_snack_since = now; gc_snack_hidden = false; }
  }
  if (gc_snack_hidden || message.empty()) return 0;
  const double age = now - gc_snack_since;
  if (age > 5.15) { gc_snack_hidden = true; return 0; }
  const float enter = gc_ease_out(static_cast<float>(age / 0.25));
  const float exit_alpha = age > 5.0 ? 1.0f - static_cast<float>((age - 5.0) / 0.15) : 1.0f;
  const float text_w = gc_text_size(gc_font_regular, GC_BODY, message).x;
  const float w = ImMax(360.0f, text_w + 32.0f + (undo ? 76.0f : 0.0f) + 44.0f);
  const float h = 48.0f;
  const float x = (panel_min.x + panel_max.x - w) * 0.5f;
  const float y = panel_max.y - 24.0f - h + (1.0f - enter) * 16.0f;
  ImGui::SetNextWindowPos(ImVec2(x, y));
  ImGui::SetNextWindowSize(ImVec2(w, h));
  ImGui::PushStyleVar(ImGuiStyleVar_Alpha, 0.001f + 0.999f * enter * exit_alpha);
  ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 8.0f);
  ImGui::PushStyleColor(ImGuiCol_WindowBg, GC_SNACKBAR);
  ImGui::Begin("##snackbar", nullptr, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoFocusOnAppearing | ImGuiWindowFlags_NoNav);
  ImDrawList* draw = ImGui::GetWindowDrawList();
  const ImVec2 p = ImGui::GetWindowPos();
  gc_text(draw, gc_font_regular, GC_BODY, ImVec2(p.x + 16.0f, p.y + 15.0f), GC_WHITE, message);
  float bx = p.x + w - 6.0f - 36.0f;
  ImGui::SetCursorScreenPos(ImVec2(bx, p.y + 6.0f));
  if (ImGui::InvisibleButton("##snackbar.dismiss", ImVec2(36.0f, 36.0f))) gc_snack_hidden = true;
  if (ImGui::IsItemHovered()) draw->AddRectFilled(ImVec2(bx, p.y + 6.0f), ImVec2(bx + 36.0f, p.y + 42.0f), IM_COL32(255, 255, 255, 30), 6.0f);
  gc_icon(draw, GC_ICON_CLOSE, ImVec2(bx + 10.0f, p.y + 16.0f), 16.0f, IM_COL32(209, 217, 224, 255));
  if (undo) {
    bx -= 76.0f;
    ImGui::SetCursorScreenPos(ImVec2(bx, p.y + 6.0f));
    if (ImGui::InvisibleButton("##snackbar.undo", ImVec2(72.0f, 36.0f))) { action = 26; gc_snack_hidden = true; }
    if (ImGui::IsItemHovered()) draw->AddRectFilled(ImVec2(bx, p.y + 6.0f), ImVec2(bx + 72.0f, p.y + 42.0f), IM_COL32(255, 255, 255, 30), 6.0f);
    gc_text(draw, gc_font_bold, GC_BODY, ImVec2(bx + (72.0f - gc_text_size(gc_font_bold, GC_BODY, "Undo").x) * 0.5f, p.y + 15.0f), IM_COL32(128, 204, 255, 255), "Undo");
  }
  ImGui::End();
  ImGui::PopStyleColor();
  ImGui::PopStyleVar(2);
  return action;
}

// ---------------------------------------------------------------------------
// Frame

extern "C" int github_client_imgui_render(
  GLFWwindow* window, int page, int busy, int progress_done, int progress_total, int flags,
  uint16_t* nav_text, uint16_t* header_text, uint16_t* rows_text, uint16_t* repositories_text,
  uint16_t* suggestions_text, uint16_t* credentials_text, uint16_t* banners_text, uint16_t* loading_text,
  uint16_t* snackbar_text, uint16_t* alert_text, uint16_t* token_text, uint16_t* page_error_text
) {
  ImGui_ImplOpenGL3_NewFrame();
  ImGui_ImplGlfw_NewFrame();
  ImGui::NewFrame();
  const double now = ImGui::GetTime();

  GcFrame frame;
  frame.page = page;
  frame.busy = busy;
  frame.progress_done = progress_done;
  frame.progress_total = progress_total;
  frame.has_credentials = (flags & 1) != 0;
  frame.cancellable = (flags & 2) != 0;
  frame.nav = gc_fields(nav_text);
  frame.header = gc_fields(header_text);
  frame.rows = gc_lines(rows_text);
  frame.repositories = gc_lines(repositories_text);
  frame.suggestions = gc_lines(suggestions_text);
  frame.credentials = gc_lines(credentials_text);
  frame.banners = gc_lines(banners_text);
  frame.loading = gc_fields(loading_text);
  frame.snackbar = gc_fields(snackbar_text);
  frame.alert = gc_fields(alert_text);
  frame.token = gc_fields(token_text);
  frame.page_error = gc_fields(page_error_text);

  if (page != gc_last_page) { gc_last_page = page; gc_page_changed_at = now; }

  int action = 0;
  ImGuiIO& io = ImGui::GetIO();
  ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f));
  ImGui::SetNextWindowSize(io.DisplaySize);
  ImGui::Begin("##app.shell", nullptr, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
  const int nav_action = gc_render_nav(frame, io.DisplaySize.y);
  if (nav_action) action = nav_action;

  const ImVec2 panel_min(244.0f, 12.0f);
  const ImVec2 panel_max(io.DisplaySize.x - 12.0f, io.DisplaySize.y - 12.0f);
  ImDrawList* shell = ImGui::GetWindowDrawList();
  shell->AddRectFilled(ImVec2(panel_min.x + 1.0f, panel_min.y + 3.0f), ImVec2(panel_max.x + 1.0f, panel_max.y + 3.0f), IM_COL32(31, 35, 40, 14), 12.0f);
  shell->AddRectFilled(panel_min, panel_max, GC_WHITE, 12.0f);
  shell->AddRect(panel_min, panel_max, GC_BORDER, 12.0f);
  const float panel_w = panel_max.x - panel_min.x - 2.0f;
  const float panel_h = panel_max.y - panel_min.y - 12.0f;
  // Page change: the workspace content fades in and rises 8 px over 150 ms.
  const float page_t = gc_ease_out(static_cast<float>((now - gc_page_changed_at) / 0.15));
  ImGui::SetCursorPos(ImVec2(panel_min.x + 1.0f, panel_min.y + 1.0f + (1.0f - page_t) * 8.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_Alpha, 0.001f + 0.999f * page_t);
  ImGui::BeginChild("##workspace", ImVec2(panel_w, panel_h), ImGuiChildFlags_None, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
  const float content_w = ImGui::GetContentRegionAvail().x;
  {
    const char* titles[] = {"Inbox", "Repositories", "Inbox", "Inbox", "Settings", "For you", "Saved"};
    const int title_index = (page >= 0 && page <= 6) ? page : 0;
    ImDrawList* draw = ImGui::GetWindowDrawList();
    const ImVec2 p = ImGui::GetCursorScreenPos();
    gc_text(draw, gc_font_bold, GC_TITLE, ImVec2(p.x + 24.0f, p.y + 20.0f), GC_FG, titles[title_index]);
    const bool activity_page = page == 0 || page == 5 || page == 6;
    float subtitle_max = p.x + content_w - 24.0f;
    if (activity_page && frame.has_credentials) {
      const float refresh_w = gc_button_width("Refresh", GC_ICON_REFRESH);
      ImGui::SetCursorScreenPos(ImVec2(p.x + content_w - 24.0f - refresh_w, p.y + 26.0f));
      if (gc_button("##activity.refresh", "Refresh", GC_BUTTON_DEFAULT, GC_ICON_REFRESH, busy != 0)) {
        action = page == 5 ? 21 : page == 6 ? 32 : 20;
      }
      const std::string synced = gc_field(frame.header, 1);
      const float sw = gc_text_size(gc_font_regular, 12.0f, synced).x;
      gc_text(draw, gc_font_regular, 12.0f, ImVec2(p.x + content_w - 24.0f - refresh_w - 12.0f - sw, p.y + 34.0f), GC_MUTED, synced);
      subtitle_max = p.x + content_w - 24.0f - refresh_w - 24.0f - sw;
    }
    gc_text_ellipsis(gc_font_regular, 13.0f, ImVec2(p.x + 24.0f, p.y + 54.0f), subtitle_max, GC_MUTED, gc_field(frame.header, 0));
    if (busy == 1) {
      gc_progress_bar(draw, ImVec2(p.x + 24.0f, p.y + 80.0f), ImVec2(p.x + content_w - 24.0f, p.y + 83.0f), progress_done, progress_total, now);
    }
    if (page == 1 || page == 4 || page == 6 || !frame.has_credentials) {
      draw->AddLine(ImVec2(p.x, p.y + 90.0f), ImVec2(p.x + content_w, p.y + 90.0f), GC_BORDER);
    }
    ImGui::SetCursorScreenPos(ImVec2(p.x, p.y + 90.0f));
  }
  int page_action = 0;
  if (page == 1) page_action = gc_render_repositories(frame, content_w);
  else if (page == 4) page_action = gc_render_settings(frame, content_w);
  else page_action = gc_render_activity_page(frame, content_w, now);
  if (page_action) action = page_action;
  ImGui::EndChild();
  ImGui::PopStyleVar();
  ImGui::End();

  int overlay = gc_render_row_menu();
  if (overlay) action = overlay;
  overlay = gc_render_snackbar(frame, panel_min, panel_max, now);
  if (overlay) action = overlay;
  overlay = gc_render_token_dialog(frame, now);
  if (overlay) action = overlay;
  overlay = gc_render_confirm_remove();
  if (overlay) action = overlay;
  overlay = gc_render_alert(frame);
  if (overlay) action = overlay;
  overlay = gc_render_loading_dialog(frame, now);
  if (overlay) action = overlay;

  ImGui::Render();
  int width = 0, height = 0;
  glfwGetFramebufferSize(window, &width, &height);
  glViewport(0, 0, width, height);
  glClearColor(0.965f, 0.973f, 0.980f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
  return action;
}

// ---------------------------------------------------------------------------
// Values staged by the last action, and view state read by MoonBit

extern "C" moonbit_string_t github_client_imgui_take_repository(void) {
  const std::string value = gc_watch_request;
  gc_watch_request.clear();
  gc_repository_input[0] = '\0';
  return gc_moonbit_string(value);
}
extern "C" moonbit_string_t github_client_imgui_take_credential_scope(void) { return gc_moonbit_string(gc_scope_input); }
extern "C" moonbit_string_t github_client_imgui_take_token(void) { return gc_moonbit_string(gc_token_input); }
extern "C" moonbit_string_t github_client_imgui_take_selected_credential(void) { return gc_moonbit_string(gc_selected_credential); }
extern "C" moonbit_string_t github_client_imgui_take_selected_repository(void) { return gc_moonbit_string(gc_selected_repository); }
extern "C" moonbit_string_t github_client_imgui_take_url(void) { return gc_moonbit_string(gc_selected_url); }
extern "C" moonbit_string_t github_client_imgui_take_activity_updated_at(void) { return gc_moonbit_string(gc_selected_updated_at); }
extern "C" moonbit_string_t github_client_imgui_take_key(void) { return gc_moonbit_string(gc_selected_key); }

extern "C" int github_client_imgui_view_kind(void) { return gc_view_kind; }
extern "C" moonbit_string_t github_client_imgui_view_repository(void) { return gc_moonbit_string(gc_view_repository); }
extern "C" moonbit_string_t github_client_imgui_view_query(void) { return gc_moonbit_string(gc_query_input); }
extern "C" moonbit_string_t github_client_imgui_view_reason(void) { return gc_moonbit_string(gc_view_reason); }
extern "C" int github_client_imgui_view_show_done(void) { return gc_show_done ? 1 : 0; }
extern "C" int github_client_imgui_auto_refresh_enabled(void) { return gc_auto_refresh_enabled ? 1 : 0; }

extern "C" void github_client_imgui_set_show_done(int value) { gc_show_done = value != 0; }
extern "C" void github_client_imgui_set_view_kind(int value) { gc_view_kind = ImClamp(value, 0, 2); }
extern "C" void github_client_imgui_set_view_repository(const uint16_t* value) { gc_view_repository = gc_utf8(value); }
extern "C" void github_client_imgui_set_view_query(const uint16_t* value) {
  std::snprintf(gc_query_input, sizeof(gc_query_input), "%s", gc_utf8(value).c_str());
}
extern "C" void github_client_imgui_set_view_reason(const uint16_t* value) { gc_view_reason = gc_utf8(value); }

extern "C" void github_client_imgui_open_row_menu(const uint16_t* url, const uint16_t* repository) {
  gc_menu_url = gc_utf8(url);
  gc_menu_repository = gc_utf8(repository);
  ImGuiIO& io = ImGui::GetIO();
  gc_menu_anchor = ImVec2(io.DisplaySize.x - 60.0f, 250.0f);
  gc_menu_request = true;
}

extern "C" void github_client_imgui_stage(
  const uint16_t* url, const uint16_t* updated_at, const uint16_t* repository, const uint16_t* key
) {
  gc_selected_url = gc_utf8(url);
  gc_selected_updated_at = gc_utf8(updated_at);
  const std::string repository_text = gc_utf8(repository);
  if (!repository_text.empty()) {
    gc_watch_request = repository_text;
    gc_selected_repository = repository_text;
    gc_selected_credential = repository_text;
  }
  gc_selected_key = gc_utf8(key);
}

extern "C" moonbit_string_t github_client_imgui_format_clock(int64_t epoch_seconds) {
  const std::time_t value = static_cast<std::time_t>(epoch_seconds);
  std::tm local {};
#ifdef _WIN32
  localtime_s(&local, &value);
#else
  localtime_r(&value, &local);
#endif
  char text[16];
  std::strftime(text, sizeof(text), "%H:%M", &local);
  return gc_moonbit_string(text);
}

extern "C" void github_client_imgui_shutdown(void) {
  ImGui_ImplOpenGL3_Shutdown();
  ImGui_ImplGlfw_Shutdown();
  ImGui::DestroyContext();
}

extern "C" double github_client_imgui_now(void) { return ImGui::GetTime(); }

// Wall-clock seconds with sub-millisecond resolution, for profiling. ImGui's
// time only advances once per frame.
extern "C" double github_client_imgui_clock(void) {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

// Ends the process after flushing output. Used only when a fetch task that
// ignores cancellation would otherwise keep the process alive.
extern "C" void github_client_imgui_exit(int code) {
  std::fflush(nullptr);
  std::_Exit(code);
}
