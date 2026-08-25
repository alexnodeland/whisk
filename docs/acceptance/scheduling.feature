# Maps to: Tests/SweepSchedulerTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §3, ADR 0004
Feature: When sweeps happen

  Scenario: Age rules wake the app without filesystem events
    Given a file that will satisfy an olderThan bound in 30 minutes
    Then a wake-up is armed for that instant, clamped to [30s, 1h]

  Scenario: Events debounce into one sweep
    Given a burst of FSEvents for one target
    Then a single sweep runs after the debounce interval

  Scenario: The safety net always runs
    Given no events and no age bounds
    Then a full rescan still happens on the rescan cadence
