#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#include <moonbit.h>

#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "../../vendor/imgui/imgui.cpp"
#include "../../vendor/imgui/imgui_draw.cpp"
#include "../../vendor/imgui/imgui_tables.cpp"
#include "../../vendor/imgui/imgui_widgets.cpp"
#include "../../vendor/imgui/backends/imgui_impl_glfw.cpp"
#include "../../vendor/imgui/backends/imgui_impl_opengl3.cpp"

static void github_client_apply_material_theme() {
  ImGuiStyle& style = ImGui::GetStyle();
  ImGui::StyleColorsLight();
  style.WindowPadding = ImVec2(20.0f, 20.0f);
  style.FramePadding = ImVec2(14.0f, 8.0f);
  style.ItemSpacing = ImVec2(12.0f, 10.0f);
  style.ItemInnerSpacing = ImVec2(8.0f, 6.0f);
  style.ScrollbarSize = 10.0f;
  style.WindowRounding = 0.0f;
  style.ChildRounding = 16.0f;
  style.FrameRounding = 8.0f;
  style.PopupRounding = 14.0f;
  style.ScrollbarRounding = 8.0f;
  style.GrabRounding = 8.0f;
  style.TabRounding = 8.0f;
  style.WindowBorderSize = 0.0f;
  style.ChildBorderSize = 1.0f;
  style.FrameBorderSize = 0.0f;

  ImVec4* colors = style.Colors;
  // GitHub Primer light palette: neutral canvas and borders, blue links,
  // and green primary actions.
  colors[ImGuiCol_Text] = ImVec4(0.122f, 0.137f, 0.157f, 1.0f);       // #1f2328
  colors[ImGuiCol_TextDisabled] = ImVec4(0.349f, 0.388f, 0.431f, 1.0f); // #59636e
  colors[ImGuiCol_WindowBg] = ImVec4(0.965f, 0.973f, 0.980f, 1.0f);   // #f6f8fa
  colors[ImGuiCol_ChildBg] = ImVec4(1.0f, 1.0f, 1.0f, 1.0f);
  colors[ImGuiCol_PopupBg] = ImVec4(1.0f, 1.0f, 1.0f, 0.99f);
  colors[ImGuiCol_Border] = ImVec4(0.816f, 0.843f, 0.871f, 1.0f);     // #d0d7de
  colors[ImGuiCol_FrameBg] = ImVec4(0.965f, 0.973f, 0.980f, 1.0f);
  colors[ImGuiCol_FrameBgHovered] = ImVec4(0.918f, 0.933f, 0.949f, 1.0f);
  colors[ImGuiCol_FrameBgActive] = ImVec4(0.867f, 0.957f, 1.0f, 1.0f);
  colors[ImGuiCol_Button] = ImVec4(0.965f, 0.973f, 0.980f, 1.0f);     // #f6f8fa
  colors[ImGuiCol_ButtonHovered] = ImVec4(0.918f, 0.933f, 0.949f, 1.0f);
  colors[ImGuiCol_ButtonActive] = ImVec4(0.816f, 0.843f, 0.871f, 1.0f);
  colors[ImGuiCol_Header] = ImVec4(0.867f, 0.957f, 1.0f, 1.0f);       // #ddf4ff
  colors[ImGuiCol_HeaderHovered] = ImVec4(0.918f, 0.933f, 0.949f, 1.0f);
  colors[ImGuiCol_HeaderActive] = ImVec4(0.741f, 0.902f, 1.0f, 1.0f);
  colors[ImGuiCol_Separator] = ImVec4(0.816f, 0.843f, 0.871f, 1.0f);
  colors[ImGuiCol_ScrollbarBg] = ImVec4(0.965f, 0.973f, 0.980f, 1.0f);
  colors[ImGuiCol_ScrollbarGrab] = ImVec4(0.686f, 0.725f, 0.765f, 1.0f);
  colors[ImGuiCol_TitleBg] = ImVec4(0.965f, 0.973f, 0.980f, 1.0f);
  colors[ImGuiCol_TitleBgActive] = ImVec4(0.965f, 0.973f, 0.980f, 1.0f);
  colors[ImGuiCol_CheckMark] = ImVec4(0.035f, 0.412f, 0.855f, 1.0f);  // #0969da
}

static void github_client_load_fonts() {
  ImGuiIO& io = ImGui::GetIO();
  io.IniFilename = nullptr;
#ifdef _WIN32
  ImFont* base = io.Fonts->AddFontFromFileTTF(
    "C:\\Windows\\Fonts\\segoeui.ttf",
    18.0f
  );
  if (base != nullptr) {
    io.FontDefault = base;
    ImFontConfig japanese_config;
    japanese_config.MergeMode = true;
    japanese_config.PixelSnapH = true;
    io.Fonts->AddFontFromFileTTF(
      "C:\\Windows\\Fonts\\meiryo.ttc",
      18.0f,
      &japanese_config,
      io.Fonts->GetGlyphRangesJapanese()
    );
  }
#endif
}

extern "C" int github_client_imgui_init(GLFWwindow* window) {
  if (window == nullptr) {
    return 0;
  }

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  github_client_apply_material_theme();
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

static char github_client_repository_input[256] = "";
static char github_client_token_input[512] = "";
static std::string github_client_selected_url;
static std::string github_client_selected_activity_updated_at;
static std::string github_client_selected_repository;
static bool github_client_unread_only = false;

struct GithubClientRow {
  std::string label;
  std::string url;
  bool is_read;
  std::string updated_at;
};

static std::string github_client_utf16_to_utf8(const uint16_t* source) {
  std::string result;
  size_t index = 0;
  while (source != nullptr && source[index] != 0) {
    uint32_t codepoint = source[index++];
    if (codepoint >= 0xD800 && codepoint <= 0xDBFF) {
      const uint32_t low = source[index];
      if (low >= 0xDC00 && low <= 0xDFFF) {
        ++index;
        codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
      } else {
        codepoint = 0xFFFD;
      }
    } else if (codepoint >= 0xDC00 && codepoint <= 0xDFFF) {
      codepoint = 0xFFFD;
    }

    if (codepoint <= 0x7F) {
      result.push_back(static_cast<char>(codepoint));
    } else if (codepoint <= 0x7FF) {
      result.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
      result.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else if (codepoint <= 0xFFFF) {
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

static std::vector<GithubClientRow> github_client_parse_rows(
  const uint16_t* source
) {
  const std::string payload = github_client_utf16_to_utf8(source);
  std::vector<GithubClientRow> rows;
  size_t start = 0;
  while (start < payload.size()) {
    const size_t end = payload.find('\n', start);
    const std::string line = payload.substr(
      start,
      end == std::string::npos ? std::string::npos : end - start
    );
    if (!line.empty()) {
      const size_t first = line.find('\t');
      const size_t second = first == std::string::npos
        ? std::string::npos
        : line.find('\t', first + 1);
      const size_t third = second == std::string::npos
        ? std::string::npos
        : line.find('\t', second + 1);
      const std::string url = first == std::string::npos
        ? ""
        : line.substr(
            first + 1,
            second == std::string::npos ? std::string::npos : second - first - 1
          );
      const std::string state = second == std::string::npos
        ? ""
        : line.substr(
            second + 1,
            third == std::string::npos ? std::string::npos : third - second - 1
          );
      rows.push_back({
        line.substr(0, first),
        url,
        state == "read",
        third == std::string::npos ? "" : line.substr(third + 1)
      });
    }
    if (end == std::string::npos) {
      break;
    }
    start = end + 1;
  }
  return rows;
}

static bool github_client_contains_case_insensitive(
  const std::string& value,
  const std::string& query
) {
  if (query.empty()) {
    return true;
  }
  std::string normalized_value = value;
  std::string normalized_query = query;
  for (char& character : normalized_value) {
    character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
  }
  for (char& character : normalized_query) {
    character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
  }
  return normalized_value.find(normalized_query) != std::string::npos;
}

static void github_client_push_primary_button_style() {
  ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 255));
  ImGui::PushStyleColor(ImGuiCol_Button, IM_COL32(31, 136, 61, 255));
  ImGui::PushStyleColor(ImGuiCol_ButtonHovered, IM_COL32(26, 127, 55, 255));
  ImGui::PushStyleColor(ImGuiCol_ButtonActive, IM_COL32(17, 99, 41, 255));
}

static void github_client_draw_folder_icon(
  ImDrawList* draw,
  const ImVec2& position,
  bool selected,
  bool hovered,
  float scale = 1.0f
) {
  const ImU32 border = IM_COL32(9, 105, 218, selected ? 255 : 150);
  const ImU32 paper = IM_COL32(255, 255, 255, 255);
  const ImU32 back = selected
    ? IM_COL32(84, 174, 255, 255)
    : hovered ? IM_COL32(191, 219, 255, 255) : IM_COL32(208, 215, 222, 255);
  const ImU32 front = selected
    ? IM_COL32(221, 244, 255, 245)
    : IM_COL32(246, 248, 250, 245);
  const float lift = selected ? 3.0f * scale : hovered ? 1.5f * scale : 0.0f;
  draw->AddRectFilled(
    ImVec2(position.x + 3.0f * scale, position.y + 3.0f * scale),
    ImVec2(position.x + 20.0f * scale, position.y + 17.0f * scale),
    back,
    4.0f * scale
  );
  draw->AddRectFilled(
    ImVec2(position.x + 6.0f * scale, position.y - lift),
    ImVec2(position.x + 17.0f * scale, position.y + 13.0f * scale - lift),
    paper,
    2.5f * scale
  );
  draw->AddRect(
    ImVec2(position.x + 6.0f * scale, position.y - lift),
    ImVec2(position.x + 17.0f * scale, position.y + 13.0f * scale - lift),
    IM_COL32(208, 215, 222, 255),
    2.5f * scale
  );
  draw->AddRectFilled(
    ImVec2(position.x, position.y + 7.0f * scale),
    ImVec2(position.x + 23.0f * scale, position.y + 20.0f * scale),
    front,
    4.0f * scale
  );
  draw->AddRect(
    ImVec2(position.x, position.y + 7.0f * scale),
    ImVec2(position.x + 23.0f * scale, position.y + 20.0f * scale),
    border,
    4.0f * scale,
    0,
    1.0f
  );
}

static bool github_client_navigation_item(
  const char* id,
  const char* label,
  bool selected,
  int unread_count = 0
) {
  const ImVec2 position = ImGui::GetCursorScreenPos();
  const ImVec2 size(ImGui::GetContentRegionAvail().x, 44.0f);
  const bool clicked = ImGui::InvisibleButton(id, size);
  const bool hovered = ImGui::IsItemHovered();
  ImDrawList* draw = ImGui::GetWindowDrawList();
  if (selected || hovered) {
    draw->AddRectFilled(
      position,
      ImVec2(position.x + size.x, position.y + size.y),
      selected ? IM_COL32(221, 244, 255, 255) : IM_COL32(234, 238, 242, 255),
      10.0f
    );
  }
  if (selected) {
    draw->AddRectFilled(
      ImVec2(position.x, position.y + 9.0f),
      ImVec2(position.x + 3.0f, position.y + size.y - 9.0f),
      IM_COL32(9, 105, 218, 255),
      2.0f
    );
  }
  github_client_draw_folder_icon(
    draw,
    ImVec2(position.x + 13.0f, position.y + 11.0f),
    selected,
    hovered
  );
  draw->AddText(
    ImVec2(position.x + 48.0f, position.y + 12.0f),
    selected ? IM_COL32(31, 35, 40, 255) : IM_COL32(89, 99, 110, 255),
    label
  );
  if (unread_count > 0) {
    const std::string count = std::to_string(unread_count);
    const ImVec2 text_size = ImGui::CalcTextSize(count.c_str());
    const float right = position.x + size.x - 10.0f;
    draw->AddRectFilled(
      ImVec2(right - text_size.x - 14.0f, position.y + 11.0f),
      ImVec2(right, position.y + 33.0f),
      selected ? IM_COL32(9, 105, 218, 255) : IM_COL32(208, 215, 222, 255),
      11.0f
    );
    draw->AddText(
      ImVec2(right - text_size.x - 7.0f, position.y + 12.0f),
      selected ? IM_COL32(255, 255, 255, 255) : IM_COL32(89, 99, 110, 255),
      count.c_str()
    );
  }
  return clicked;
}

static int github_client_unread_count(const std::vector<GithubClientRow>& rows) {
  int count = 0;
  for (const GithubClientRow& row : rows) {
    if (!row.is_read) {
      ++count;
    }
  }
  return count;
}

static void github_client_draw_header_folder(
  ImDrawList* draw,
  const ImVec2& position
) {
  for (int index = 0; index < 3; ++index) {
    const float offset = static_cast<float>(index) * 7.0f;
    draw->AddRectFilled(
      ImVec2(position.x + 12.0f + offset, position.y - 8.0f - offset),
      ImVec2(position.x + 55.0f + offset, position.y + 31.0f - offset),
      IM_COL32(255, 255, 255, 255),
      8.0f
    );
    draw->AddRect(
      ImVec2(position.x + 12.0f + offset, position.y - 8.0f - offset),
      ImVec2(position.x + 55.0f + offset, position.y + 31.0f - offset),
      IM_COL32(208, 215, 222, 255),
      8.0f
    );
  }
  draw->AddRectFilled(
    ImVec2(position.x, position.y + 9.0f),
    ImVec2(position.x + 78.0f, position.y + 51.0f),
    IM_COL32(221, 244, 255, 245),
    12.0f
  );
  draw->AddRect(
    ImVec2(position.x, position.y + 9.0f),
    ImVec2(position.x + 78.0f, position.y + 51.0f),
    IM_COL32(9, 105, 218, 200),
    12.0f
  );
}

static void github_client_render_activity_rows(
  const std::vector<GithubClientRow>& rows,
  int* action
) {
  const int unread_count = github_client_unread_count(rows);
  ImGui::PushStyleColor(ImGuiCol_ChildBg, IM_COL32(246, 248, 250, 255));
  ImGui::BeginChild(
    "##activity.toolbar",
    ImVec2(ImGui::GetContentRegionAvail().x, 52.0f),
    ImGuiChildFlags_None
  );
  ImGui::SetCursorPos(ImVec2(14.0f, 9.0f));
  ImGui::AlignTextToFramePadding();
  ImGui::TextDisabled("%d unread", unread_count);
  ImGui::SameLine();
  ImGui::TextDisabled("· %d total", static_cast<int>(rows.size()));
  const float filter_width = 128.0f;
  ImGui::SameLine(ImGui::GetWindowWidth() - filter_width - 12.0f);
  ImGui::Checkbox("Unread only##activity.unread-only", &github_client_unread_only);
  ImGui::EndChild();
  ImGui::PopStyleColor();
  ImGui::Dummy(ImVec2(0.0f, 6.0f));

  const ImGuiTableFlags table_flags = ImGuiTableFlags_SizingStretchProp;
  if (ImGui::BeginTable("##activity.rows", 4, table_flags)) {
    ImGui::TableSetupColumn("State", ImGuiTableColumnFlags_WidthFixed, 58.0f);
    ImGui::TableSetupColumn("Activity", ImGuiTableColumnFlags_WidthStretch);
    ImGui::TableSetupColumn("Open", ImGuiTableColumnFlags_WidthFixed, 82.0f);
    ImGui::TableSetupColumn("Read action", ImGuiTableColumnFlags_WidthFixed, 128.0f);
    for (const GithubClientRow& row : rows) {
      if (github_client_unread_only && row.is_read) {
        continue;
      }
      ImGui::PushID(row.url.c_str());
      ImGui::TableNextRow(0, 48.0f);
      ImGui::TableSetColumnIndex(0);
      ImGui::AlignTextToFramePadding();
      if (row.is_read) {
        ImGui::TextDisabled("Read");
      } else {
        ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(9, 105, 218, 255));
        ImGui::TextUnformatted("Unread");
        ImGui::PopStyleColor();
      }
      ImGui::TableSetColumnIndex(1);
      ImGui::AlignTextToFramePadding();
      if (row.is_read) {
        ImGui::TextDisabled("%s", row.label.c_str());
      } else {
        ImGui::TextUnformatted(row.label.c_str());
      }
      ImGui::TableSetColumnIndex(2);
      ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(9, 105, 218, 255));
      if (ImGui::Button("Open##activity.open", ImVec2(76.0f, 32.0f))) {
        github_client_selected_url = row.url;
        github_client_selected_activity_updated_at = row.updated_at;
        *action = 4;
      }
      ImGui::PopStyleColor();
      ImGui::TableSetColumnIndex(3);
      const char* toggle_label = row.is_read
        ? "Mark unread##activity.toggle"
        : "Mark read##activity.toggle";
      if (ImGui::Button(toggle_label, ImVec2(122.0f, 32.0f))) {
        github_client_selected_url = row.url;
        github_client_selected_activity_updated_at = row.updated_at;
        *action = 6;
      }
      ImGui::PopID();
    }
    ImGui::EndTable();
  }
}

extern "C" int github_client_imgui_render(
  GLFWwindow* window,
  int page,
  int sign_in_requests,
  int repository_count,
  int has_saved_token,
  uint16_t* repositories_text,
  uint16_t* suggested_repositories_text,
  uint16_t* pull_requests_text,
  uint16_t* issues_text,
  uint16_t* personal_activity_text,
  uint16_t* sync_status_text
) {
  ImGui_ImplOpenGL3_NewFrame();
  ImGui_ImplGlfw_NewFrame();
  ImGui::NewFrame();

  int action = 0;
  bool open_pat_popup = false;
  const std::vector<GithubClientRow> repositories =
    github_client_parse_rows(repositories_text);
  const std::vector<GithubClientRow> suggested_repositories =
    github_client_parse_rows(suggested_repositories_text);
  const std::vector<GithubClientRow> pull_requests =
    github_client_parse_rows(pull_requests_text);
  const std::vector<GithubClientRow> issues =
    github_client_parse_rows(issues_text);
  const std::vector<GithubClientRow> personal_activity =
    github_client_parse_rows(personal_activity_text);
  const std::string sync_status = github_client_utf16_to_utf8(sync_status_text);
  if (page < 0 || page > 5) {
    page = 0;
  }
  const char* page_titles[] = {
    "Inbox", "Repositories", "Pull requests", "Issues", "Settings", "For you"
  };
  const char* page_descriptions[] = {
    "Activity from Watched repositories and their dependencies.",
    "Choose repositories to watch or select one from your GitHub account.",
    "Review relevant pull requests across monitored repositories.",
    "Track issues from Watched repositories in one place.",
    "Manage authentication and application preferences.",
    "Personal activity from Watched repositories only."
  };
  const char* recent_titles[] = {
    "Watched activity", "Watched repositories", "Relevant pull requests",
    "Relevant issues", "Credential", "Items involving you"
  };
  const char* empty_messages[] = {
    "No Watched repository activity needs your attention.",
    "No repositories registered yet.",
    "No relevant pull requests found.",
    "No relevant issues found.",
    "No credential is configured.",
    "No personal activity was found in Watched repositories."
  };
  ImGuiIO& io = ImGui::GetIO();
  ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f));
  ImGui::SetNextWindowSize(io.DisplaySize);
  const ImGuiWindowFlags shell_flags =
    ImGuiWindowFlags_NoDecoration |
    ImGuiWindowFlags_NoMove |
    ImGuiWindowFlags_NoSavedSettings |
    ImGuiWindowFlags_NoBringToFrontOnFocus;
  ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0.0f, 0.0f));
  ImGui::Begin("##app.shell", nullptr, shell_flags);
  ImGui::PopStyleVar();

  ImDrawList* draw = ImGui::GetWindowDrawList();
  const ImVec2 origin = ImGui::GetWindowPos();
  const int inbox_unread = github_client_unread_count(pull_requests)
    + github_client_unread_count(issues);
  const int personal_unread = github_client_unread_count(personal_activity);

  ImGui::SetCursorPos(ImVec2(0.0f, 0.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 0.0f);
  ImGui::PushStyleColor(ImGuiCol_ChildBg, IM_COL32(246, 248, 250, 255));
  ImGui::BeginChild(
    "##navigation",
    ImVec2(232.0f, io.DisplaySize.y),
    ImGuiChildFlags_None
  );
  ImGui::PopStyleColor();
  ImGui::PopStyleVar();

  ImGui::SetCursorPos(ImVec2(20.0f, 22.0f));
  const ImVec2 brand_position = ImGui::GetCursorScreenPos();
  draw = ImGui::GetWindowDrawList();
  draw->AddRectFilled(
    brand_position,
    ImVec2(brand_position.x + 38.0f, brand_position.y + 38.0f),
    IM_COL32(37, 41, 46, 255),
    12.0f
  );
  draw->AddText(
    ImVec2(brand_position.x + 8.0f, brand_position.y + 9.0f),
    IM_COL32(255, 255, 255, 255),
    "GH"
  );
  draw->AddText(
    ImVec2(brand_position.x + 50.0f, brand_position.y + 1.0f),
    IM_COL32(31, 35, 40, 255),
    "GitHub Client"
  );
  draw->AddText(
    ImVec2(brand_position.x + 50.0f, brand_position.y + 22.0f),
    IM_COL32(89, 99, 110, 255),
    "MoonBit native"
  );

  ImGui::SetCursorPos(ImVec2(18.0f, 92.0f));
  ImGui::TextDisabled("ACTIVITY");
  ImGui::SetCursorPosX(12.0f);
  if (github_client_navigation_item(
        "##nav.inbox", "Inbox", page == 0, inbox_unread
      )) {
    action = 10;
  }
  ImGui::SetCursorPosX(12.0f);
  if (github_client_navigation_item(
        "##nav.for-you", "For you", page == 5, personal_unread
      )) {
    action = 15;
  }
  ImGui::SetCursorPosX(12.0f);
  if (github_client_navigation_item(
        "##nav.pull-requests", "Pull requests", page == 2
      )) {
    action = 12;
  }
  ImGui::SetCursorPosX(12.0f);
  if (github_client_navigation_item("##nav.issues", "Issues", page == 3)) {
    action = 13;
  }

  ImGui::SetCursorPos(ImVec2(18.0f, 330.0f));
  ImGui::TextDisabled("MANAGE");
  ImGui::SetCursorPosX(12.0f);
  if (github_client_navigation_item(
        "##nav.repositories", "Repositories", page == 1
      )) {
    action = 11;
  }
  ImGui::SetCursorPosX(12.0f);
  if (github_client_navigation_item("##nav.settings", "Settings", page == 4)) {
    action = 14;
  }

  ImGui::SetCursorPos(ImVec2(20.0f, io.DisplaySize.y - 50.0f));
  ImGui::TextDisabled("WINDOWS · NATIVE");
  ImGui::EndChild();

  const ImVec2 panel_min(origin.x + 244.0f, origin.y + 12.0f);
  const ImVec2 panel_max(
    origin.x + io.DisplaySize.x - 12.0f,
    origin.y + io.DisplaySize.y - 12.0f
  );
  draw = ImGui::GetWindowDrawList();
  draw->AddRectFilled(
    ImVec2(panel_min.x + 2.0f, panel_min.y + 5.0f),
    ImVec2(panel_max.x + 2.0f, panel_max.y + 5.0f),
    IM_COL32(31, 35, 40, 18),
    22.0f
  );
  ImGui::SetCursorPos(ImVec2(244.0f, 12.0f));
  ImGui::PushStyleColor(ImGuiCol_ChildBg, IM_COL32(255, 255, 255, 255));
  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 22.0f);
  ImGui::BeginChild(
    "##content",
    ImVec2(io.DisplaySize.x - 256.0f, io.DisplaySize.y - 24.0f),
    ImGuiChildFlags_Borders
  );
  ImGui::PopStyleVar();
  ImGui::PopStyleColor();

  ImGui::SetCursorPos(ImVec2(28.0f, 24.0f));
  ImGui::TextDisabled(page == 4 || page == 1 ? "MANAGE" : "ACTIVITY");
  ImGui::SetCursorPosX(28.0f);
  ImGui::SetWindowFontScale(1.25f);
  ImGui::TextUnformatted(page_titles[page]);
  ImGui::SetWindowFontScale(1.0f);
  ImGui::SetCursorPosX(28.0f);
  ImGui::TextDisabled("%s", page_descriptions[page]);
  github_client_draw_header_folder(
    ImGui::GetWindowDrawList(),
    ImVec2(
      ImGui::GetWindowPos().x + ImGui::GetWindowWidth() - 112.0f,
      ImGui::GetWindowPos().y + 36.0f
    )
  );
  ImGui::SetCursorPos(ImVec2(28.0f, 116.0f));

  const float card_width = ImGui::GetContentRegionAvail().x - 8.0f;
  if (page == 4) {
    ImGui::BeginChild("##credential.card", ImVec2(card_width, 210.0f),
                      ImGuiChildFlags_Borders);
    ImGui::TextUnformatted(
      has_saved_token ? "GitHub credential is protected" : "Connect your GitHub account"
    );
    ImGui::Spacing();
    ImGui::TextWrapped(
      has_saved_token
        ? "A personal access token is encrypted with the operating system credential store."
        : "Add a fine-grained personal access token. It is encrypted before being written to disk."
    );
    ImGui::Dummy(ImVec2(0.0f, 12.0f));
    github_client_push_primary_button_style();
    const char* credential_button = has_saved_token
      ? "Replace token##auth.sign-in"
      : "Add token##auth.sign-in";
    if (ImGui::Button(credential_button, ImVec2(174.0f, 42.0f))) {
      open_pat_popup = true;
      action = 1;
    }
    ImGui::PopStyleColor(4);
    ImGui::SameLine();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("Interaction count: %d", sign_in_requests);
    if (!sync_status.empty()) {
      ImGui::TextDisabled("%s", sync_status.c_str());
    }
    ImGui::EndChild();
  } else {
    ImGui::BeginChild("##activity.card", ImGui::GetContentRegionAvail(),
                      ImGuiChildFlags_Borders);
    ImGui::TextUnformatted(recent_titles[page]);
    ImGui::Separator();
    if (page == 1) {
      ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - 190.0f);
      ImGui::InputTextWithHint(
        "##repository.register.input",
        "Filter or enter owner/repository",
        github_client_repository_input,
        sizeof(github_client_repository_input)
      );
      ImGui::SameLine();
      github_client_push_primary_button_style();
      if (ImGui::Button("Watch##repository.register", ImVec2(150.0f, 0.0f))) {
        action = 2;
      }
      ImGui::PopStyleColor(4);
      ImGui::TextDisabled("Watched: %d", repository_count);
      if (!sync_status.empty()) {
        ImGui::SameLine();
        ImGui::TextDisabled("%s", sync_status.c_str());
      }
      if (repositories.empty()) {
        ImGui::TextDisabled("No repositories are watched yet.");
      }
      for (const GithubClientRow& repository : repositories) {
        const float right_edge =
          ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x;
        ImGui::AlignTextToFramePadding();
        ImGui::TextUnformatted(repository.label.c_str());
        ImGui::SameLine(right_edge - 100.0f);
        ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(207, 34, 46, 255));
        ImGui::PushStyleColor(ImGuiCol_Button, IM_COL32(246, 248, 250, 255));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, IM_COL32(255, 235, 233, 255));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, IM_COL32(255, 206, 203, 255));
        const std::string remove_id = "Remove##watched.remove." + repository.label;
        if (ImGui::Button(remove_id.c_str(), ImVec2(100.0f, 34.0f))) {
          github_client_selected_repository = repository.label;
          action = 5;
        }
        ImGui::PopStyleColor(4);
        ImGui::Separator();
      }
      ImGui::Spacing();
      ImGui::Separator();
      ImGui::TextUnformatted("Your repositories");
      ImGui::TextDisabled("Use the explicit Watch action to add a repository.");
      if (suggested_repositories.empty()) {
        ImGui::TextDisabled("No repository suggestions are available for this token.");
      }
      for (const GithubClientRow& suggestion : suggested_repositories) {
        if (!github_client_contains_case_insensitive(
              suggestion.url,
              github_client_repository_input
            )) {
          continue;
        }
        bool watched = false;
        for (const GithubClientRow& repository : repositories) {
          if (repository.label == suggestion.url) {
            watched = true;
            break;
          }
        }
        const float right_edge =
          ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x;
        ImGui::AlignTextToFramePadding();
        ImGui::TextUnformatted(suggestion.label.c_str());
        ImGui::SameLine(right_edge - 100.0f);
        if (watched) {
          ImGui::BeginDisabled();
          const std::string watched_id = "Watched##suggestion." + suggestion.url;
          ImGui::Button(watched_id.c_str(), ImVec2(100.0f, 34.0f));
          ImGui::EndDisabled();
        } else {
          github_client_push_primary_button_style();
          const std::string watch_id = "Watch##suggestion." + suggestion.url;
          if (ImGui::Button(watch_id.c_str(), ImVec2(100.0f, 34.0f))) {
            std::snprintf(
              github_client_repository_input,
              sizeof(github_client_repository_input),
              "%s",
              suggestion.url.c_str()
            );
            action = 2;
          }
          ImGui::PopStyleColor(4);
        }
        ImGui::Separator();
      }
    } else {
      std::vector<GithubClientRow> visible_rows;
      if (page == 0) {
        visible_rows.insert(visible_rows.end(), pull_requests.begin(), pull_requests.end());
        visible_rows.insert(visible_rows.end(), issues.begin(), issues.end());
      } else if (page == 2) {
        visible_rows = pull_requests;
      } else if (page == 3) {
        visible_rows = issues;
      } else if (page == 5) {
        visible_rows = personal_activity;
      }
      if (visible_rows.empty()) {
        ImGui::TextDisabled("%s", empty_messages[page]);
      } else {
        github_client_render_activity_rows(visible_rows, &action);
      }
    }
    ImGui::EndChild();
  }
  ImGui::EndChild();
  ImGui::End();

  if (open_pat_popup) {
    ImGui::OpenPopup("Personal access token##auth.pat-dialog");
  }
  ImGui::SetNextWindowSize(ImVec2(560.0f, 0.0f), ImGuiCond_Appearing);
  if (ImGui::BeginPopupModal(
        "Personal access token##auth.pat-dialog",
        nullptr,
        ImGuiWindowFlags_AlwaysAutoResize
      )) {
    ImGui::TextWrapped(
      "The token stays masked and is encrypted with Windows DPAPI before storage."
    );
    ImGui::Spacing();
    ImGui::SetNextItemWidth(520.0f);
    ImGui::InputTextWithHint(
      "##auth.pat-input",
      "github_pat_...",
      github_client_token_input,
      sizeof(github_client_token_input),
      ImGuiInputTextFlags_Password
    );
    ImGui::Spacing();
    github_client_push_primary_button_style();
    if (ImGui::Button("Save securely##auth.pat-save", ImVec2(160.0f, 40.0f))) {
      action = 3;
      ImGui::CloseCurrentPopup();
    }
    ImGui::PopStyleColor(4);
    ImGui::SameLine();
    ImGui::PushStyleColor(ImGuiCol_Button, IM_COL32(246, 248, 250, 255));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, IM_COL32(234, 238, 242, 255));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, IM_COL32(208, 215, 222, 255));
    if (ImGui::Button("Cancel##auth.pat-cancel", ImVec2(110.0f, 40.0f))) {
      github_client_token_input[0] = '\0';
      ImGui::CloseCurrentPopup();
    }
    ImGui::PopStyleColor(3);
    ImGui::EndPopup();
  }

  ImGui::Render();
  int width = 0;
  int height = 0;
  glfwGetFramebufferSize(window, &width, &height);
  glViewport(0, 0, width, height);
  glClearColor(0.08f, 0.09f, 0.12f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
  return action;
}

extern "C" moonbit_string_t github_client_imgui_take_repository(void) {
  const size_t length = std::strlen(github_client_repository_input);
  moonbit_string_t result = moonbit_make_string(length, 0);
  for (size_t index = 0; index < length; ++index) {
    result[index] = static_cast<uint16_t>(
      static_cast<unsigned char>(github_client_repository_input[index])
    );
  }
  github_client_repository_input[0] = '\0';
  return result;
}

extern "C" moonbit_string_t github_client_imgui_take_selected_repository(void) {
  const size_t length = github_client_selected_repository.size();
  moonbit_string_t result = moonbit_make_string(length, 0);
  for (size_t index = 0; index < length; ++index) {
    result[index] = static_cast<uint16_t>(
      static_cast<unsigned char>(github_client_selected_repository[index])
    );
  }
  github_client_selected_repository.clear();
  return result;
}

extern "C" moonbit_string_t github_client_imgui_take_url(void) {
  const size_t length = github_client_selected_url.size();
  moonbit_string_t result = moonbit_make_string(length, 0);
  for (size_t index = 0; index < length; ++index) {
    result[index] = static_cast<uint16_t>(
      static_cast<unsigned char>(github_client_selected_url[index])
    );
  }
  github_client_selected_url.clear();
  return result;
}

extern "C" moonbit_string_t github_client_imgui_take_activity_updated_at(void) {
  const size_t length = github_client_selected_activity_updated_at.size();
  moonbit_string_t result = moonbit_make_string(length, 0);
  for (size_t index = 0; index < length; ++index) {
    result[index] = static_cast<uint16_t>(
      static_cast<unsigned char>(github_client_selected_activity_updated_at[index])
    );
  }
  github_client_selected_activity_updated_at.clear();
  return result;
}

extern "C" moonbit_string_t github_client_imgui_take_token(void) {
  const size_t length = std::strlen(github_client_token_input);
  moonbit_string_t result = moonbit_make_string(length, 0);
  for (size_t index = 0; index < length; ++index) {
    result[index] = static_cast<uint16_t>(
      static_cast<unsigned char>(github_client_token_input[index])
    );
  }
  std::memset(github_client_token_input, 0, sizeof(github_client_token_input));
  return result;
}

extern "C" void github_client_imgui_shutdown(void) {
  ImGui_ImplOpenGL3_Shutdown();
  ImGui_ImplGlfw_Shutdown();
  ImGui::DestroyContext();
}
