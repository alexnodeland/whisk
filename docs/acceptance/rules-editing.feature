Feature: Editing rules in the GUI
  The editor is a hand on the same file the user writes: saves preserve their
  comments (ADR 0013), state their outcome, and never surprise.

  Background:
    Given a rules file with a header comment, a commented rule "shots",
      and a disabled rule "keep" carrying an inner comment

  Scenario: Saving without changes keeps every comment
    When the editor saves an unchanged draft
    Then the header, per-rule, inner, and trailing comments all survive
    And the file still decodes to the same rule set

  Scenario: Editing one rule keeps its lead comment and the others verbatim
    When the "shots" rule is disabled in the editor and saved
    Then the comment above "shots" survives
    And the untouched "keep" rule keeps its inner comment

  Scenario: Deleting and reordering rules moves comments with their rules
    When rules are reordered or removed and saved
    Then each surviving rule's comments travel with it
    And a deleted rule's comments are gone with it

  Scenario: Only the targets section is rewritten
    Given the file has version, defaults, and unknown top-level keys
    When the editor saves
    Then everything outside "targets" is byte-identical in content

  Scenario: A malformed original falls back to strict encoding
    Given the rules file on disk cannot be parsed
    When the editor saves
    Then the draft is written as strict JSON (there was nothing to preserve)

  Scenario: The editor shows its state honestly
    Given the draft differs from the file
    Then an "Unsaved changes" badge shows and Save is enabled
    When the save lands and hot-reloads
    Then the badge clears and a transient "Saved" confirmation appears
    And Save and Revert are disabled while the draft matches the file

  Scenario: Thresholds are picked, not typed as codes
    Given the age and size conditions in the rule form
    Then age is a number with a minutes/hours/days/weeks unit picker
    And size is a number with a KB/MB/GB unit picker
    And clearing the number removes the condition ("any age" / "any size")
