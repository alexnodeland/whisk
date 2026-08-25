# Acceptance traceability

Each feature file maps to the XCTest suites named in its header; the unit
suites run under the hard 100% coverage gate (`just coverage`), and the
integration/smoke scripts exercise the same behavior against the real system.

| Feature | Verified by |
| --- | --- |
| rules-parsing | RuleParserTests, RuleModelTests, UnitsTests |
| matching | ConditionEvaluatorTests, GlobMatcherTests, FileFactsTests |
| patterns | PatternRendererTests |
| planning | SweepPlannerTests, SweepCoordinatorTests, scripts/integration-test.sh |
| loop-guard | LoopGuardTests, SweepPlannerTests, SweepCoordinatorTests, integration (budget case) |
| scheduling | SweepSchedulerTests, SweepCoordinatorTests |
| shell-safety | ShellApprovalTests, SweepCoordinatorTests |
| notifications | NotificationPlannerTests, SweepCoordinatorTests |
| activity-log | ActivityLogTests, SweepCoordinatorTests, integration (JSONL assertions) |
| rules-reload | SweepCoordinatorTests |
| pause-and-dry-run | AppSettingsTests, SweepCoordinatorTests |
| url-scheme | WhiskRouteTests, SweepCoordinatorTests, scripts/smoke-test.sh |
| updates | UpdatePlannerTests, UpdateCoordinatorTests, AppSettingsTests |
| settings | AppSettingsTests (appearance + update policy persistence); window itself is presentation, checked manually below |
| rules-editing | RulesTextTests (comment preservation, merge semantics); editor chrome is presentation, checked manually below |

## Manual checklists (per release)

- [ ] `just smoke` in a GUI session (FSEvents sweep + whisk://sweep)
- [ ] First-launch TCC prompt appears for ~/Downloads; denial shows the badge
- [ ] Notification permission prompt appears once; notices arrive
- [ ] Editor round-trip: change a rule in the GUI, confirm the file updated and
      hot-reload swept
- [ ] ⌘, (or the menu's Settings…) opens Settings; all five tabs render;
      toggles persist across a relaunch; About shows the right version;
      Activity lists entries; a pending shell command can be approved,
      revoked from Setup, and is then held again
- [ ] Editor: dirty badge appears on edit, Save flashes "Saved", a commented
      file keeps its comments after a GUI save, and the age/size pickers
      write the expected conditions
- [ ] Unit pickers hold a chosen unit (minutes/hours/weeks, KB/GB) instead of
      snapping back; switching the Appearance icon changes the live menu bar
      item; the Settings Activity tab shows full columns and can be resized
- [ ] `brew install --cask alexnodeland/tap/whisk` on a clean machine
