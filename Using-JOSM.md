## How to connect to Places with JOSM

*If you already have a token/secret, start at step 3*

###\#1 Get the desired User's ID

```sql
SELECT
  users.id as "User ID"
  users.display_name AS "User Name"
FROM
  user
WHERE
  users.display_name LIKE '%DESIRED USER'S LAST NAME%'
```

###\#2 Add a non-expiring active session for that user

```sql
INSERT INTO oauth_tokens 
            (id, 
             user_id, 
             TYPE, 
             client_application_id,  -- We do -1 to prevent stepping on an indexes
             token, 
             secret, 
             authorized_at, 
             invalidated_at, 
             created_at, 
             updated_at, 
             allow_read_prefs, 
             allow_write_prefs, 
             allow_write_diary, 
             allow_write_api, 
             allow_read_gpx, 
             allow_write_gpx) 
VALUES      ( 0, 
             1,  -- This needs to be changed to match the user's id
             'AccessToken', 
             0, -- This needs to match the application key (0 is JOSM) 
             'wp0VBUceQL4XKIyuKweUFhvLg2Xnqvfq08HNtG5g', -- This can be any key
             'tghTvu8TFj0XUhSmLFSogSZTEwTmfB1yjNQV7bvR', -- This can be any secret
             Now(), 
             NULL, 
             '3000-01-01', 
             Now(), 
             TRUE, 
             TRUE, 
             TRUE, 
             TRUE, 
             TRUE, 
             TRUE);
```

###\#3 Download JOSM
You can download JOSM from [this link](https://josm.openstreetmap.de/wiki/Download).

###\#4 Open JOSM and navigate to "Connection Settings"
1. JOSM -> Preferences
2. Click the "World" button (should be 2nd from the top in the left)

###\#5 Change the OSM Server URL
1. The Places server URL is: `http://10.147.153.193/api`

The validate button doesn't work with Places.

###\#6 Create a new Access Token
1. Click the `New Acces Token` button
2. From the `Please select an authorization procedure` dropdown, select `Manual`
3. Next to `Access Token Key`, enter the access token key from your query in step one
4. Next to `Access Token Secret`, enter the access token secret from your query in step one
5. Make sure the `Save Access Token in preferences` checkbox is checked
6. Click `Test Access Token`, your username should be displayed
7. If that works, click the `Accept Access Token` button
8. Press `Ok` on the Preferences screen, and you are read to start editing Places with JOSM

###\#7 TODO: JOSM Tutorial 
In the meantime, there are some great JOSM tutorials online.

The most up-to-date guide is usually: [The OpenStreetMap Wiki JOSM Guide](http://wiki.openstreetmap.org/wiki/JOSM/Guide).
