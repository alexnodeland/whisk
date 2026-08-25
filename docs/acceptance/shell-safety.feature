# Maps to: Tests/ShellApprovalTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §4, ADR 0007
Feature: Shell command safety

  Scenario: New commands are held for approval
    Given a run action whose (command, args) pair was never approved
    Then nothing executes; the pair is held, notified once, and shown in the menu

  Scenario: Approval is immediate and verbatim
    When the user approves the held pair
    Then the command runs at once with argv-only arguments, the file path
      appended, a sanitized environment, and the rule's timeout

  Scenario: A changed command needs re-approval
    Given an approved command whose args template changed
    Then the new pair is held again

  Scenario: Failures are recorded and notified
    Given a command that exits non-zero, times out, or fails to launch
    Then the activity log records the reason and captured output
