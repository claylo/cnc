spec_helper_setup() {
  TEST_TMPDIR=$(mktemp -d)
}

spec_helper_cleanup() {
  rm -rf "$TEST_TMPDIR"
}

spec_helper_configure() {
  before_each "spec_helper_setup"
  after_each "spec_helper_cleanup"
}
