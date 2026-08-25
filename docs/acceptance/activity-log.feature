# Maps to: Tests/ActivityLogTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §5
Feature: Activity log

  Scenario: Every executed action becomes one JSONL line
    Given executed actions with ok/error/skipped/preview outcomes
    Then each maps to a single stable-keyed JSON line that round-trips

  Scenario: Retention prunes at launch
    Given a log holding entries older than 30 days or beyond 1000 entries
    When Whisk starts
    Then the excess is pruned and the file rewritten once; garbage lines are tolerated
