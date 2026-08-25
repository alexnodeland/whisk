# Maps to: Tests/AppSettingsTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §5
Feature: Pause and dry-run

  Scenario: Pause blocks sweeps until it lapses or is resumed
    Given a pause for one hour or until resumed
    Then triggered sweeps do nothing, Run Now still works, and resume catches up

  Scenario: Dry-run previews without touching
    Given dry-run mode
    Then planned actions log and notify as previews and no filesystem effect or
      shell command happens
