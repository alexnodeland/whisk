Feature: Self-updating
  Whisk checks for new releases daily and can install them itself, so no
  machine is left running a stale build (ADR 0012).

  Background:
    Given the app is running version "0.1.1"

  Scenario: A daily check finds a newer release
    Given the latest published release is "0.2.0" with a universal zip asset
    And automatic update checks are enabled
    When the background check runs
    Then the menu shows "Whisk 0.2.0 is available" with an Install button
    And a notification is posted for "0.2.0" once, not on every later check

  Scenario: The running version is current
    Given the latest published release is "0.1.1"
    When the background check runs
    Then no update is offered and no notification is posted

  Scenario: A check is only due once per day
    Given a check ran less than 24 hours ago
    When the hourly timer fires
    Then no network request is made

  Scenario: Automatic checks can be turned off
    Given "Check for updates automatically" is off
    When the hourly timer fires
    Then no network request is made

  Scenario: Auto-install is opt-in
    Given "Install updates automatically" is on
    And the latest published release is "0.2.0"
    When the background check runs
    Then the zip is downloaded and the installer replaces the bundle
    And no "available" notification is posted, because the install is the answer

  Scenario: A manual check reports and offers, it never installs on its own
    Given "Install updates automatically" is on
    When the user clicks Check Now
    Then the update is announced with an Install button
    And nothing installs until the user clicks it

  Scenario: A failed download does not strand the app
    Given an update to "0.2.0" is known
    When the download fails
    Then the progress state clears and a failure notification is posted

  Scenario: The installer refuses a bad archive
    Given the downloaded archive does not contain a Whisk.app
    Then nothing is replaced and the failure is reported

  Scenario: A malformed release payload is ignored
    Given the latest-release endpoint returns something unparsable
    When the background check runs
    Then the known update state is unchanged

  Scenario: Update notifications honor the global switch
    Given notifications are disabled
    And the latest published release is "0.2.0"
    When the background check runs
    Then the menu shows the update but no notification is posted
