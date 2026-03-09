Describe 'handoff-filename-guard.sh'
  GUARD="hooks/handoff-filename-guard.sh"
  FROZEN_TS="2026-03-09-1430"

  setup() {
    # Freeze time for deterministic tests
    export FROZEN_TS
    date() { echo "$FROZEN_TS"; }
    export -f date
  }

  BeforeEach 'setup'

  Describe 'stale timestamp'
    It 'blocks and returns corrected path'
      Data '{"tool_input":{"file_path":"/proj/.handoffs/2025-01-15-0900-migration-plan.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"block"'
      The output should include "/proj/.handoffs/${FROZEN_TS}-migration-plan.md"
    End
  End

  Describe 'lazy format (rounded minutes)'
    It 'blocks and returns corrected path'
      Data '{"tool_input":{"file_path":"/proj/.handoffs/20260308-1200-lazy-handoff.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"block"'
      The output should include "/proj/.handoffs/${FROZEN_TS}-lazy-handoff.md"
    End
  End

  Describe 'extra digits (seconds appended)'
    It 'blocks and returns corrected path'
      Data '{"tool_input":{"file_path":"/proj/.handoffs/2026-03-08-192300-feature-work.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"block"'
      The output should include "/proj/.handoffs/${FROZEN_TS}-feature-work.md"
    End
  End

  Describe 'current timestamp'
    It 'allows the write'
      Data
        #|{"tool_input":{"file_path":"/proj/.handoffs/2026-03-09-1430-good-handoff.md"}}
      End
      When run script "$GUARD"
      The output should include '"permissionDecision":"allow"'
      The output should include 'handoff filename OK'
    End
  End

  Describe 'non-handoff path'
    It 'exits silently with success'
      Data '{"tool_input":{"file_path":"/proj/src/main.rs"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End
  End
End
