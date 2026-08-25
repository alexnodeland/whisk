# Maps to: Tests/RuleParserTests.swift, Tests/RuleModelTests.swift, Tests/UnitsTests.swift
# Cross-references: RFC 0001 §2, ADR 0003
Feature: Rules file parsing and validation

  Scenario: JSON5 relaxations are accepted
    Given a rules file with comments, trailing commas, and unquoted keys
    When Whisk parses it
    Then the rule set loads successfully

  Scenario: Unit-suffixed literals parse
    Given size literals like "100KB" and duration literals like "7d"
    When they are decoded
    Then they become bytes and seconds, and reject garbage like "7" or "100TB"

  Scenario: A malformed file yields a one-line diagnostic
    Given a rules file with a syntax error, a missing key, or a wrong type
    When Whisk parses it
    Then the failure names the problem and the coding path (e.g. targets[0].rules[2])

  Scenario: Semantic validation rejects unsafe rules
    Given duplicate rule ids, empty condition groups, malformed globs or regexes,
      relative run commands, out-of-range timeouts, or actions after move/trash
    When Whisk validates the parsed set
    Then each produces a named diagnostic and the set is rejected

  Scenario: The editor's strict JSON round-trips
    Given any valid rule set
    When it is encoded by the editor and parsed again
    Then the result equals the original
