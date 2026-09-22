#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#include <moonbit.h>

#include <cstring>

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
  style.FramePadding = ImVec2(14.0f, 9.0f);
  style.ItemSpacing = ImVec2(12.0f, 10.0f);
  style.ItemInnerSpacing = ImVec2(8.0f, 6.0f);
  style.ScrollbarSize = 12.0f;
  style.WindowRounding = 0.0f;
  style.ChildRounding = 10.0f;
  style.FrameRounding = 6.0f;
  style.PopupRounding = 8.0f;
  style.ScrollbarRounding = 8.0f;
  style.GrabRounding = 6.0f;
  style.TabRounding = 6.0f;
  style.WindowBorderSize = 0.0f;
  style.ChildBorderSize = 1.0f;
  style.FrameBorderSize = 0.0f;

  ImVec4* colors = style.Colors;
  colors[ImGuiCol_Text] = ImVec4(0.13f, 0.13f, 0.13f, 1.0f);
  colors[ImGuiCol_TextDisabled] = ImVec4(0.46f, 0.46f, 0.46f, 1.0f);
  colors[ImGuiCol_WindowBg] = ImVec4(0.96f, 0.96f, 0.97f, 1.0f);
  colors[ImGuiCol_ChildBg] = ImVec4(1.0f, 1.0f, 1.0f, 1.0f);
  colors[ImGuiCol_PopupBg] = ImVec4(1.0f, 1.0f, 1.0f, 0.98f);
  colors[ImGuiCol_Border] = ImVec4(0.88f, 0.88f, 0.90f, 1.0f);
  colors[ImGuiCol_FrameBg] = ImVec4(0.94f, 0.94f, 0.95f, 1.0f);
  colors[ImGuiCol_FrameBgHovered] = ImVec4(0.89f, 0.93f, 0.98f, 1.0f);
  colors[ImGuiCol_FrameBgActive] = ImVec4(0.82f, 0.89f, 0.97f, 1.0f);
  colors[ImGuiCol_Button] = ImVec4(0.10f, 0.46f, 0.82f, 1.0f);
  colors[ImGuiCol_ButtonHovered] = ImVec4(0.08f, 0.40f, 0.75f, 1.0f);
  colors[ImGuiCol_ButtonActive] = ImVec4(0.06f, 0.34f, 0.68f, 1.0f);
  colors[ImGuiCol_Header] = ImVec4(0.89f, 0.93f, 0.98f, 1.0f);
  colors[ImGuiCol_HeaderHovered] = ImVec4(0.82f, 0.89f, 0.97f, 1.0f);
  colors[ImGuiCol_HeaderActive] = ImVec4(0.73f, 0.84f, 0.95f, 1.0f);
  colors[ImGuiCol_Separator] = ImVec4(0.88f, 0.88f, 0.90f, 1.0f);
  colors[ImGuiCol_ScrollbarBg] = ImVec4(0.96f, 0.96f, 0.97f, 1.0f);
  colors[ImGuiCol_ScrollbarGrab] = ImVec4(0.70f, 0.70f, 0.73f, 1.0f);
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

extern "C" int github_client_imgui_render(
  GLFWwindow* window,
  int page,
  int sign_in_requests,
  int repository_count,
  int has_saved_token
) {
  ImGui_ImplOpenGL3_NewFrame();
  ImGui_ImplGlfw_NewFrame();
  ImGui::NewFrame();

  int action = 0;
  if (page < 0 || page > 3) {
    page = 0;
  }
  const char* page_titles[] = {
    "Inbox", "Repositories", "Pull requests", "Issues"
  };
  const char* page_descriptions[] = {
    "Relevant activity from registered repositories and their dependencies.",
    "Choose the repositories this client should monitor.",
    "Review relevant pull requests across monitored repositories.",
    "Track relevant issues and mentions in one place."
  };
  const char* recent_titles[] = {
    "Relevant activity", "Registered repositories", "Relevant pull requests", "Relevant issues"
  };
  const char* empty_messages[] = {
    "Nothing relevant needs your attention.",
    "No repositories registered yet.",
    "No relevant pull requests found.",
    "No relevant issues found."
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
  draw->AddRectFilled(
    origin,
    ImVec2(origin.x + io.DisplaySize.x, origin.y + 64.0f),
    IM_COL32(25, 118, 210, 255)
  );
  draw->AddCircleFilled(ImVec2(origin.x + 32.0f, origin.y + 32.0f), 17.0f,
                        IM_COL32(255, 255, 255, 38));

  ImGui::SetCursorPos(ImVec2(22.0f, 20.0f));
  ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 255));
  ImGui::TextUnformatted("GH");
  ImGui::SetCursorPos(ImVec2(60.0f, 20.0f));
  ImGui::TextUnformatted("MoonBit GitHub Client");
  ImGui::PopStyleColor();

  ImGui::SetCursorPos(ImVec2(0.0f, 64.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 0.0f);
  ImGui::BeginChild("##navigation", ImVec2(232.0f, io.DisplaySize.y - 64.0f),
                    ImGuiChildFlags_Borders);
  ImGui::PopStyleVar();
  ImGui::Dummy(ImVec2(0.0f, 8.0f));
  ImGui::TextDisabled("  NAVIGATION");
  ImGui::Spacing();
  if (ImGui::Selectable("  Inbox##nav.inbox", page == 0, 0,
                        ImVec2(0.0f, 44.0f))) {
    action = 10;
  }
  if (ImGui::Selectable("  Repositories##nav.repositories", page == 1, 0,
                        ImVec2(0.0f, 44.0f))) {
    action = 11;
  }
  if (ImGui::Selectable("  Pull requests##nav.pull-requests", page == 2, 0,
                        ImVec2(0.0f, 44.0f))) {
    action = 12;
  }
  if (ImGui::Selectable("  Issues##nav.issues", page == 3, 0,
                        ImVec2(0.0f, 44.0f))) {
    action = 13;
  }
  ImGui::EndChild();

  ImGui::SetCursorPos(ImVec2(264.0f, 92.0f));
  ImGui::BeginChild(
    "##content",
    ImVec2(io.DisplaySize.x - 296.0f, io.DisplaySize.y - 116.0f),
    ImGuiChildFlags_None
  );
  ImGui::TextUnformatted(page_titles[page]);
  ImGui::TextDisabled("%s", page_descriptions[page]);
  ImGui::Dummy(ImVec2(0.0f, 10.0f));

  const float card_width = ImGui::GetContentRegionAvail().x;
  ImGui::BeginChild("##welcome.card", ImVec2(card_width, 226.0f),
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
  ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 255));
  const char* credential_button = has_saved_token
    ? "Replace token##auth.sign-in"
    : "Add token##auth.sign-in";
  if (ImGui::Button(credential_button, ImVec2(174.0f, 42.0f))) {
    ImGui::OpenPopup("Personal access token##auth.pat-dialog");
    action = 1;
  }
  ImGui::PopStyleColor();
  ImGui::SameLine();
  ImGui::AlignTextToFramePadding();
  ImGui::TextDisabled("Interaction count: %d", sign_in_requests);
  ImGui::EndChild();

  ImGui::Dummy(ImVec2(0.0f, 12.0f));
  ImGui::BeginChild("##recent.card", ImVec2(card_width, 150.0f),
                    ImGuiChildFlags_Borders);
  ImGui::TextUnformatted(recent_titles[page]);
  ImGui::Separator();
  if (page == 1) {
    ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - 190.0f);
    ImGui::InputTextWithHint(
      "##repository.register.input",
      "owner/repository",
      github_client_repository_input,
      sizeof(github_client_repository_input)
    );
    ImGui::SameLine();
    ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 255));
    if (ImGui::Button("Register##repository.register", ImVec2(150.0f, 0.0f))) {
      action = 2;
    }
    ImGui::PopStyleColor();
    ImGui::TextDisabled("Registered: %d", repository_count);
  } else {
    ImGui::TextDisabled("%s", empty_messages[page]);
  }
  ImGui::EndChild();
  ImGui::EndChild();
  ImGui::End();

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
    ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(255, 255, 255, 255));
    if (ImGui::Button("Save securely##auth.pat-save", ImVec2(160.0f, 40.0f))) {
      action = 3;
      ImGui::CloseCurrentPopup();
    }
    ImGui::PopStyleColor();
    ImGui::SameLine();
    if (ImGui::Button("Cancel##auth.pat-cancel", ImVec2(110.0f, 40.0f))) {
      github_client_token_input[0] = '\0';
      ImGui::CloseCurrentPopup();
    }
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
