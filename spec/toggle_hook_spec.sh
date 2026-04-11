Describe 'toggle-hook.sh (cncflip)'
  HOOK="$PWD/hooks/toggle-hook.sh"

  setup() {
    export HOME="$TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/.claude"
    echo '{"sandbox":{"enabled":false}}' > "$TEST_TMPDIR/.claude/settings.local.json"
    cd "$TEST_TMPDIR"
  }

  BeforeEach 'setup'

  Describe 'list with no argument'
    It 'shows all hooks as on by default'
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'handoff-filename-guard: on'
      The output should include 'for-the-record: on'
      The output should include 'rustfmt-on-save: on'
      The output should include 'session-start: on'
    End

    It 'accepts plugin-namespaced /cnc:cncflip form'
      Data '{"user_prompt":"/cnc:cncflip"}'
      When run script "$HOOK"
      The output should include 'handoff-filename-guard: on'
    End
  End

  Describe 'toggle off'
    It 'flips to OFF'
      Data '{"user_prompt":"/cncflip for-the-record"}'
      When run script "$HOOK"
      The output should include 'Toggled for-the-record'
      The output should include 'OFF'
    End

    It 'flips via plugin-namespaced /cnc:cncflip form'
      Data '{"user_prompt":"/cnc:cncflip for-the-record"}'
      When run script "$HOOK"
      The output should include 'Toggled for-the-record'
      The output should include 'OFF'
    End
  End

  Describe 'list with a hook disabled'
    setup_disabled() {
      export HOME="$TEST_TMPDIR"
      mkdir -p "$TEST_TMPDIR/.claude"
      echo '{"sandbox":{},"cnc":{"hooks":{"for-the-record":false}}}' > "$TEST_TMPDIR/.claude/settings.local.json"
      cd "$TEST_TMPDIR"
    }

    BeforeEach 'setup_disabled'

    It 'shows OFF for disabled hook'
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'for-the-record: OFF'
      The output should include 'handoff-filename-guard: on'
    End

    It 'flips back to on'
      Data '{"user_prompt":"/cncflip for-the-record"}'
      When run script "$HOOK"
      The output should include 'Toggled for-the-record'
      The output should include 'on'
    End
  End

  Describe 'explicit true treated as enabled'
    setup_explicit_true() {
      export HOME="$TEST_TMPDIR"
      mkdir -p "$TEST_TMPDIR/.claude"
      echo '{"cnc":{"hooks":{"for-the-record":true}}}' > "$TEST_TMPDIR/.claude/settings.local.json"
      cd "$TEST_TMPDIR"
    }

    BeforeEach 'setup_explicit_true'

    It 'shows on for explicitly true hook'
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'for-the-record: on'
    End

    It 'flips explicit true to OFF'
      Data '{"user_prompt":"/cncflip for-the-record"}'
      When run script "$HOOK"
      The output should include 'Toggled for-the-record'
      The output should include 'OFF'
    End
  End

  Describe 'unknown hook name'
    It 'rejects with available list'
      Data '{"user_prompt":"/cncflip bogus"}'
      When run script "$HOOK"
      The output should include 'Unknown hook: bogus'
      The output should include 'Available:'
    End
  End

  Describe 'creates config scaffolding if missing'
    It 'works with no settings.local.json'
      rm -f "$TEST_TMPDIR/.claude/settings.local.json"
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'handoff-filename-guard: on'
    End
  End

  Describe 'global defaults'
    setup_global() {
      export HOME="$TEST_TMPDIR"
      mkdir -p "$TEST_TMPDIR/.claude"
      mkdir -p "$TEST_TMPDIR/.config/cnc"
      echo '{"sandbox":{}}' > "$TEST_TMPDIR/.claude/settings.local.json"
      echo '{"wiretap":false,"oops":true}' > "$TEST_TMPDIR/.config/cnc/defaults.json"
      cd "$TEST_TMPDIR"
    }

    BeforeEach 'setup_global'

    It 'shows global OFF with indicator'
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'wiretap: OFF (global)'
    End

    It 'shows global on with indicator'
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'oops: on (global)'
    End

    It 'shows default on for hooks not in global'
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'vent: on'
      The output should not include 'vent: on (global)'
    End

    It 'toggle overrides global at project level'
      Data '{"user_prompt":"/cncflip wiretap"}'
      When run script "$HOOK"
      The output should include 'Toggled wiretap'
      The output should include 'on'
    End
  End

  Describe '--global list'
    setup_global_list() {
      export HOME="$TEST_TMPDIR"
      mkdir -p "$TEST_TMPDIR/.claude"
      mkdir -p "$TEST_TMPDIR/.config/cnc"
      echo '{"sandbox":{}}' > "$TEST_TMPDIR/.claude/settings.local.json"
      echo '{"wiretap":false,"oops":true}' > "$TEST_TMPDIR/.config/cnc/defaults.json"
      cd "$TEST_TMPDIR"
    }

    BeforeEach 'setup_global_list'

    It 'shows only global state'
      Data '{"user_prompt":"/cncflip --global"}'
      When run script "$HOOK"
      The output should include 'global defaults'
      The output should include 'wiretap: OFF'
      The output should include 'oops: on'
      The output should include 'vent: (unset)'
    End
  End

  Describe '--global toggle'
    setup_global_toggle() {
      export HOME="$TEST_TMPDIR"
      mkdir -p "$TEST_TMPDIR/.claude"
      echo '{"sandbox":{}}' > "$TEST_TMPDIR/.claude/settings.local.json"
      cd "$TEST_TMPDIR"
    }

    BeforeEach 'setup_global_toggle'

    It 'creates defaults.json and flips to OFF'
      Data '{"user_prompt":"/cncflip --global wiretap"}'
      When run script "$HOOK"
      The output should include 'Toggled wiretap'
      The output should include 'OFF (global)'
    End

    It 'flips global OFF back to on'
      # Pre-seed global with wiretap off
      mkdir -p "$TEST_TMPDIR/.config/cnc"
      echo '{"wiretap":false}' > "$TEST_TMPDIR/.config/cnc/defaults.json"
      Data '{"user_prompt":"/cncflip --global wiretap"}'
      When run script "$HOOK"
      The output should include 'Toggled wiretap'
      The output should include 'on (global)'
    End
  End

  Describe 'project overrides global'
    setup_override() {
      export HOME="$TEST_TMPDIR"
      mkdir -p "$TEST_TMPDIR/.claude"
      mkdir -p "$TEST_TMPDIR/.config/cnc"
      echo '{"cnc":{"hooks":{"wiretap":true}}}' > "$TEST_TMPDIR/.claude/settings.local.json"
      echo '{"wiretap":false}' > "$TEST_TMPDIR/.config/cnc/defaults.json"
      cd "$TEST_TMPDIR"
    }

    BeforeEach 'setup_override'

    It 'project true overrides global false'
      Data '{"user_prompt":"/cncflip"}'
      When run script "$HOOK"
      The output should include 'wiretap: on'
      The output should not include 'wiretap: on (global)'
    End
  End
End
