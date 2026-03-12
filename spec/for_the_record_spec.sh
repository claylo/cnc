Describe 'for-the-record.sh'
  GUARD="hooks/for-the-record.sh"

  Describe 'redirects record-keeping subdirs from docs/ to record/'
    It 'redirects docs/adrs/'
      Data '{"tool_input":{"file_path":"/proj/docs/adrs/0001-use-rust.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/adrs/0001-use-rust.md"
    End

    It 'redirects docs/decisions/'
      Data '{"tool_input":{"file_path":"/proj/docs/decisions/001-use-rust.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/decisions/001-use-rust.md"
    End

    It 'redirects docs/plans/'
      Data '{"tool_input":{"file_path":"/proj/docs/plans/v2-migration.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/plans/v2-migration.md"
    End

    It 'redirects docs/reviews/'
      Data '{"tool_input":{"file_path":"/proj/docs/reviews/pr-42.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/reviews/pr-42.md"
    End

    It 'redirects docs/specs/'
      Data '{"tool_input":{"file_path":"/proj/docs/specs/yaml-parser.md"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/specs/yaml-parser.md"
    End

    It 'redirects docs/diagrams/ with nested paths'
      Data '{"tool_input":{"file_path":"/proj/docs/diagrams/arch/overview.svg"}}'
      When run script "$GUARD"
      The output should include '"permissionDecision":"deny"'
      The output should include "/proj/record/diagrams/arch/overview.svg"
    End
  End

  Describe 'allows legitimate docs/ writes'
    It 'passes through user-facing docs'
      Data '{"tool_input":{"file_path":"/proj/docs/api-reference.md"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End

    It 'passes through docs/index.html'
      Data '{"tool_input":{"file_path":"/proj/docs/index.html"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End
  End

  Describe 'ignores non-docs paths'
    It 'exits silently for src/'
      Data '{"tool_input":{"file_path":"/proj/src/main.rs"}}'
      When run script "$GUARD"
      The status should be success
      The output should eq ""
    End
  End
End
