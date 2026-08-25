# Maps to: Tests/SweepCoordinatorTests.swift
# Cross-references: RFC 0001 §2, ADR 0003
Feature: Rules file lifecycle

  Scenario: First launch seeds a starter file
    Given no rules file exists
    When Whisk starts
    Then it writes the commented seed (which itself parses) and loads it

  Scenario: Saves hot-reload
    When the rules file changes on disk
    Then Whisk reloads, re-targets the watcher, and sweeps

  Scenario: A broken save never wipes state
    Given a running Whisk and a rules file edited into a syntax error
    Then the previous rules stay active, the menu shows the diagnostic, and a
      notification fires
