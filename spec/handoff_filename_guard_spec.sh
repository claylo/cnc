Describe 'handoff-filename-guard.sh'
  GUARD="hooks/handoff-filename-guard.sh"
  FROZEN_TS="2026-03-09-1430"
  PREV_TS="2026-03-09-1429"
  TEST_HANDOFF_DIR="/tmp/cnc-test-handoffs"

  setup() {
    export FROZEN_TS PREV_TS
    date() {
      case "${1:-}" in
        -v-1M) shift; echo "$PREV_TS" ;;
        +%s)   command date +%s ;;
        *)     echo "$FROZEN_TS" ;;
      esac
    }
    export -f date
  }

  cleanup_test_files() {
    rm -rf "$TEST_HANDOFF_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup_test_files'

  Describe 'Write: stale timestamp'
    It 'blocks and returns corrected path'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/.handoffs/2025-01-15-0900-migration-plan.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/.handoffs/${FROZEN_TS}-migration-plan.md"
    End
  End

  Describe 'Write: lazy format (rounded minutes)'
    It 'blocks and returns corrected path'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/.handoffs/20260308-1200-lazy-handoff.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/.handoffs/${FROZEN_TS}-lazy-handoff.md"
    End
  End

  Describe 'Write: extra digits (seconds appended)'
    It 'blocks and returns corrected path'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/.handoffs/2026-03-08-192300-feature-work.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/.handoffs/${FROZEN_TS}-feature-work.md"
    End
  End

  Describe 'Write: current timestamp'
    It 'allows the write'
      Data
        #|{"tool_name":"Write","tool_input":{"file_path":"/proj/.handoffs/2026-03-09-1430-good-handoff.md"}}
      End
      When run script "$GUARD"
      The output should include '"permissionDecision":"allow"'
      The output should include 'handoff filename OK'
    End
  End

  Describe 'Write: off-by-one minute (cusp of minute change)'
    It 'allows the write'
      Data
        #|{"tool_name":"Write","tool_input":{"file_path":"/proj/.handoffs/2026-03-09-1429-cusp-handoff.md"}}
      End
      When run script "$GUARD"
      The output should include '"permissionDecision":"allow"'
      The output should include 'handoff filename OK'
    End
  End

  Describe 'non-handoff path'
    It 'exits silently with success'
      Data '{"tool_name":"Write","tool_input":{"file_path":"/proj/src/main.rs"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End
  End

  Describe 'Edit: historical handoff (>30min old)'
    setup_old_file() {
      mkdir -p "${TEST_HANDOFF_DIR}/.handoffs"
      touch -t 202001010000 "${TEST_HANDOFF_DIR}/.handoffs/2025-01-15-0900-old-handoff.md"
    }
    BeforeEach 'setup_old_file'

    It 'allows the edit'
      Data '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/cnc-test-handoffs/.handoffs/2025-01-15-0900-old-handoff.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"allow"'
      The output should include 'historical handoff edit allowed'
    End
  End

  Describe 'Edit: fresh handoff (<30min old) with wrong name'
    setup_fresh_file() {
      mkdir -p "${TEST_HANDOFF_DIR}/.handoffs"
      touch "${TEST_HANDOFF_DIR}/.handoffs/2026-03-09-1400-fresh-handoff.md"
    }
    BeforeEach 'setup_fresh_file'

    It 'denies the edit'
      Data '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/cnc-test-handoffs/.handoffs/2026-03-09-1400-fresh-handoff.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/tmp/cnc-test-handoffs/.handoffs/${FROZEN_TS}-fresh-handoff.md"
    End
  End

  Describe 'Edit: fresh handoff with correct name'
    setup_fresh_correct() {
      mkdir -p "${TEST_HANDOFF_DIR}/.handoffs"
      touch "${TEST_HANDOFF_DIR}/.handoffs/${FROZEN_TS}-correct-handoff.md"
    }
    BeforeEach 'setup_fresh_correct'

    It 'allows the edit'
      Data '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/cnc-test-handoffs/.handoffs/2026-03-09-1430-correct-handoff.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"allow"'
      The output should include 'handoff filename OK'
    End
  End

  Describe 'Edit: nonexistent file falls through to timestamp check'
    It 'denies with corrected path (no file to check age on)'
      Data '{"tool_name":"Edit","tool_input":{"file_path":"/proj/.handoffs/2025-06-01-0800-ghost-handoff.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/.handoffs/${FROZEN_TS}-ghost-handoff.md"
    End
  End
End
