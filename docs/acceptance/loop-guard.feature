# Maps to: Tests/LoopGuardTests.swift, Tests/SweepPlannerTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §4, ADR 0006
Feature: Runaway protection

  Scenario: Self-written paths do not re-trigger
    Given Whisk just moved a file into a watched folder
    When an FSEvent arrives for that path within the ledger window
    Then the event is dropped

  Scenario: Cooldowns stop rapid re-application
    Given a rule acted on a file moments ago
    Then the same (file, rule) pair is ineligible until the cooldown lapses

  Scenario: A runaway rule is auto-paused
    Given a rule matching more files than its per-sweep budget
    Then the budget's worth of actions run, the rule pauses (persisted), a
      notification fires, and the menu offers re-enable

  Scenario: Cycles are refused at plan time
    Given a move whose destination is the source's own directory or inside the source
    Then no action is planned
