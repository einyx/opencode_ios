"""Source integration guards; behavioral regressions live in the Swift suites."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "OpenCodeClient" / "OpenCodeClient"


class HIGIntegrationTests(unittest.TestCase):
    def source(self, path):
        return (ROOT / path).read_text()

    def test_permission_sheet_can_scroll_and_expand(self):
        source = self.source("Views/ClientCapabilityPermissionView.swift")
        self.assertIn("ScrollView", source)
        self.assertIn(".large", source)
        self.assertIn("AnyLayout", source)

    def test_host_editor_protects_unsaved_changes_and_names_commit_action(self):
        source = self.source("Views/HostProfilesView.swift")
        self.assertIn("interactiveDismissDisabled", source)
        self.assertIn("hasUnsavedChanges", source)
        self.assertIn(".hostSaveAndConnect", source)

    def test_sessions_offer_scoped_search_and_confirm_delete(self):
        for path in ["Views/SessionListView.swift", "ContentView.swift"]:
            source = self.source(path)
            self.assertIn(".searchable", source, path)
            self.assertIn(".sessionsDeleteConfirmation", source, path)

    def test_web_preview_receives_dynamic_type(self):
        source = self.source("Views/MarkdownWebPreviewView.swift")
        self.assertIn("dynamicTypeSize", source)
        self.assertIn("fontScale", source)
        self.assertIn("fontScale", self.source("Resources/WebPreview/preview.js"))

    def test_file_tree_exposes_retry_and_semantic_status(self):
        source = self.source("Views/FileTreeView.swift")
        self.assertIn("fileTreeError", source)
        self.assertIn(".commonRetry", source)
        self.assertIn(".fileStatusModified", source)

    def test_shortlist_has_non_drag_alternatives(self):
        source = self.source("Views/ModelShortlistView.swift")
        self.assertIn("accessibilityAction", source)
        self.assertIn(".moveUp", source)
        self.assertIn(".moveDown", source)

    def test_motion_is_respected_in_chat_and_tools(self):
        for path in ["Views/Chat/ChatTabView.swift", "Views/Chat/ToolPartView.swift", "Views/Chat/MessageRowView.swift"]:
            self.assertIn("accessibilityReduceMotion", self.source(path), path)

    def test_confirmed_deletion_keeps_host_ownership_at_execution(self):
        source = self.source("AppState+Sessions.swift")
        self.assertIn("expectedHost: HostRequestSnapshot?", source)
        for path in ["Views/SessionListView.swift", "ContentView.swift"]:
            self.assertIn("expectedHost: host", self.source(path))

    def test_session_picker_dismisses_only_after_successful_creation(self):
        self.assertIn("if await state.createSession()", self.source("Views/SessionListView.swift"))

    def test_composer_has_one_shared_footer_for_model_and_actions(self):
        source = self.source("Views/Chat/ChatTabView.swift")
        self.assertIn("private var composerFooter", source)
        self.assertNotIn("composerWidth < 430", source)



if __name__ == "__main__":
    unittest.main()
