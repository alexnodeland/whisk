# Maps to: Tests/SweepPlannerTests.swift, Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §3, ADR 0004/0005
Feature: Sweep planning and execution

  Scenario: Rules apply in order and move/trash consume
    Given a target with a move rule followed by a trash rule
    When both match the same file
    Then only the move is planned; the file is consumed for the rest of the sweep

  Scenario: Action chains thread the projected path
    Given rename → copy → move actions on one rule
    Then later actions operate on the renamed path

  Scenario: Relative destinations resolve against the target
    Given a move destination "Sorted/{ext}"
    Then it resolves inside the target directory

  Scenario: Plans become effects through the ports
    Given a planned move whose destination directory does not exist
    Then the executor creates it, resolves conflicts from the live listing, and records the outcome

  Scenario: A denied target surfaces instead of failing silently
    Given a target directory that cannot be enumerated
    Then the sweep marks the target denied and the menu shows a "No access" badge
