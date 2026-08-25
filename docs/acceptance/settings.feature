Feature: Settings
  Configuration lives in a standard Settings window (⌘,) with General,
  Appearance, Setup, and About tabs, so the menu bar popover stays an
  at-a-glance surface: status, Run Now, pause, dry-run, approvals, and recent
  activity.

  Scenario: The menu bar icon can be switched back to the classic glyph
    Given the default menu bar icon is the brand whisk
    When "Sparkles" is chosen in Appearance
    Then the choice persists across launches
    And either icon still signals the paused state

  Scenario: The number of recent actions in the menu is configurable
    Given the menu shows 10 recent actions by default
    When the count is set in Appearance
    Then the popover lists that many entries

  Scenario: A hand-edited recent-actions count cannot blow up the menu
    Given the persisted count was edited outside the app
    When it is out of range or not a number
    Then it reads back clamped to 1–50, or as the default when unparsable

  Scenario: Launch at login survives upgrades
    Given "Launch Whisk at login" is on
    When an upgrade replaces the app and its ad-hoc signature
    Then the stored intent re-registers the login item at next launch

  Scenario: Update policy is configured in General
    Given the "check automatically" and "install automatically" switches
    Then they persist through the same store as every other setting
    And "install automatically" is inert while checking is off
