# Maps to: Tests/WhiskRouteTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §5, scripts/smoke-test.sh
Feature: whisk:// URL scheme

  Scenario Outline: Commands parse and dispatch
    When "<url>" opens
    Then Whisk performs <effect>

    Examples:
      | url                          | effect                    |
      | whisk://sweep                | sweep every target now    |
      | whisk://pause?minutes=60     | pause for an hour         |
      | whisk://pause                | pause until resumed       |
      | whisk://resume               | resume sweeping           |
      | whisk://dry-run?enabled=true | enable preview mode       |

  Scenario: Foreign and malformed URLs are ignored
    Given an unknown host, a non-whisk scheme, or minutes=0
    Then nothing happens
