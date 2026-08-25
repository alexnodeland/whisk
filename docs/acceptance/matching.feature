# Maps to: Tests/ConditionEvaluatorTests.swift, Tests/GlobMatcherTests.swift, Tests/FileFactsTests.swift
# Cross-references: RFC 0001 §2.1
Feature: Condition matching

  Scenario: Globs match names case-insensitively
    Given the glob "*.{png,jpg}"
    Then "Shot.PNG" matches and "shot.gif" does not, and a malformed glob matches nothing

  Scenario: Size and age bounds are strict
    Given a 1000-byte file
    Then size over "999B" matches and over "1000B" does not
    And a file whose basis date is exactly the olderThan bound away does not yet match

  Scenario: Combinators nest
    Given all/any/not trees over simple conditions
    Then evaluation follows conjunction, disjunction, and negation semantics
