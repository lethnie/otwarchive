﻿@users
@admin
@wip
Feature: Archivist bulk imports

  Scenario: Log in as an archivist and import a big archive.
    Given the following admin exists
      | login       | password | 
      | EYalkut     | secret   |
      And the following activated user exists
      | login       | password      | 
      | elynross    | Yulet1de      |
    When I am logged in as "elynross" with password "Yulet1de"
      And I follow "Import"
    Then I should not see "Import works for others"
    When I follow "Log out"
      And I go to the admin_login page
      And I fill in "admin_login" with "EYalkut"
      And I fill in "admin_password" with "secret"
      And I press "Log in as admin"
      And I fill in "query" with "elynross"
      And I press "Find"
    Then I should see "elynross" within "#admin_users_table"
    When I check "user_archivist"
      And I press "Update"
    Then I should see "User was successfully updated"
    When I follow "Log out"
      And I am logged in as "elynross" with password "Yulet1de"
      And I follow "Import"
    Then I should see "Import works for others"
    When I check "Import works for others"
      And I fill in "urls" with "http://cesy.dreamwidth.org/154770.html \n http://cesy.dreamwidth.org/394320.html"
      And I check "Post without previewing"
      And I press "Import"
    Then I should see "Importing completed successfully! (But please check the results over carefully!)"
      And I should see "We have notified the author(s) you imported stories for. You can also add them as co-authors manually."
      And I should see "Imported Works"
      And I should see "We were able to successfully upload the following works."
      And I should see "Welcome"
      And I should see "OTW Meetup in London"
    Given the system processes jobs
    Then 2 emails should be delivered

