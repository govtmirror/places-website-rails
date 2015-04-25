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
