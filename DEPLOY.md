The NPS Version of the Rails-Port uses Capistrano and RVM for its deployment.
A good guide on how this was set up is [here](https://gorails.com/deploy/ubuntu/14.04).

It should be as easy as running the command:
`cap production deploy`

I haven't figured out a good way to do the secret key stuff, so for now.. after you install in, you need to run these commands:

```
sudo rm /var/www/places/current/config/secrets.yml
sudo ln -s /home/deploy/secrets.yml /var/www/places/current/config/secrets.yml
sudo service nginx restart
```
