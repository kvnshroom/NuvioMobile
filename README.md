# kvn build of Nuvio Mobile (Android)

This branch holds only the automation for a personal, unofficial Nuvio Android build.

- Branch `kvn`: the latest upstream release of
  [NuvioMedia/NuvioMobile](https://github.com/NuvioMedia/NuvioMobile) plus a few commits on
  top: the "Are you still watching?" prompt (#2206), an own package `com.nuvio.app.kvn`
  (installs next to the official app), a settable version code,
  and the updater pointing at this fork.
- Workflow `kvn android build` (daily and on demand): rebases the `kvn` commits onto the
  newest upstream release, builds the full-flavor release APKs signed with the kvn key, and
  publishes them as a release `<upstream tag>.kvn.<n>`.
- Once upstream ships a kvn feature itself (the "Are you still watching?" PR), the rebase
  leaves our commit out and keeps upstream's version. `UPSTREAMED_FEATURES` in
  `scripts/kvn-prepare.sh` lists each feature with code that proves it is upstream.
- Secrets: `KVN_RELEASE_KEYSTORE_BASE64` (signing key) and `KVN_LOCAL_PROPERTIES_BASE64`
  (Supabase values plus the keystore passwords). Losing the signing key means installed
  copies can no longer be updated, so keep its backup.

Stop using it: disable the workflow and uninstall "Nuvio kvn".
