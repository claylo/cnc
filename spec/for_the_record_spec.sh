Describe 'for-the-record.sh'
  GUARD="hooks/for-the-record.sh"
  TEST_DOCS_DIR="/tmp/cnc-test-docs"

  cleanup_test_files() {
    rm -rf "$TEST_DOCS_DIR"
  }

  AfterEach 'cleanup_test_files'

  Describe 'Write: always redirects record-keeping subdirs to record/'
    It 'redirects docs/adrs/'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/adrs/0001-use-rust.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/adrs/0001-use-rust.md"
    End

    It 'redirects docs/decisions/'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/decisions/001-use-rust.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/decisions/001-use-rust.md"
    End

    It 'redirects docs/plans/'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/plans/v2-migration.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/plans/v2-migration.md"
    End

    It 'redirects docs/reviews/'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/reviews/pr-42.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/reviews/pr-42.md"
    End

    It 'redirects docs/specs/'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/specs/yaml-parser.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/specs/yaml-parser.md"
    End

    It 'redirects docs/diagrams/ with nested paths'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/diagrams/arch/overview.svg"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/diagrams/arch/overview.svg"
    End

    It 'redirects docs/superpowers/'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/superpowers/plan-review.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/superpowers/plan-review.md"
    End
  End

  Describe 'Read: non-existent file redirects to record/'
    It 'redirects to record/decisions/'
      Data '{"tool_name":"Read","tool_input":{"file_path":"/proj/docs/decisions/001-use-rust.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "record/"
      The output should include "/proj/record/decisions/001-use-rust.md"
    End

    It 'redirects to record/plans/'
      Data '{"tool_name":"Read","tool_input":{"file_path":"/proj/docs/plans/v2-migration.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/plans/v2-migration.md"
    End
  End

  Describe 'Read: existing legacy file allowed with move suggestion'
    setup_legacy_file() {
      mkdir -p "${TEST_DOCS_DIR}/docs/decisions"
      echo "# ADR" > "${TEST_DOCS_DIR}/docs/decisions/001-use-rust.md"
    }
    BeforeEach 'setup_legacy_file'

    It 'allows read and suggests moving'
      Data '{"tool_name":"Read","tool_input":{"file_path":"/tmp/cnc-test-docs/docs/decisions/001-use-rust.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"allow"'
      The output should include 'Legacy location'
      The output should include 'mv docs/decisions/ record/decisions/'
    End
  End

  Describe 'Edit: existing legacy file allowed with move suggestion'
    setup_legacy_file() {
      mkdir -p "${TEST_DOCS_DIR}/docs/specs"
      echo "# Spec" > "${TEST_DOCS_DIR}/docs/specs/yaml-parser.md"
    }
    BeforeEach 'setup_legacy_file'

    It 'allows edit and suggests moving'
      Data '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/cnc-test-docs/docs/specs/yaml-parser.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"allow"'
      The output should include 'Legacy location'
      The output should include 'mv docs/specs/ record/specs/'
    End
  End

  Describe 'Edit: non-existent file redirects to record/'
    It 'redirects to record/specs/'
      Data '{"tool_name":"Edit","tool_input":{"file_path":"/proj/docs/specs/yaml-parser.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/specs/yaml-parser.md"
    End
  End

  Describe 'allows legitimate docs/ paths'
    It 'passes through user-facing docs'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/docs/api-reference.md"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End

    It 'passes through docs/index.html'
      Data '{"tool_name":"Read","tool_input":{"file_path":"/proj/docs/index.html"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End
  End

  Describe 'ignores non-docs paths'
    It 'exits silently for src/'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/src/main.rs"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End
  End
End
