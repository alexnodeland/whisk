# Maps to: Tests/NotificationPlannerTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §5
Feature: Notifications

  Scenario: Successes batch per rule
    Given one sweep where a rule acted on many files
    Then one notice summarizes them, eliding beyond four detail lines

  Scenario: The notify flag and the global toggle are honored
    Given a rule with notify=false, or notifications disabled globally
    Then its successes post nothing (failures still collect while the global toggle is on)

  Scenario: Dry-run notices are labeled previews
    Given dry-run mode
    Then notices carry the preview prefix
