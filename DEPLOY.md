The NPS Version of the Rails-Port uses Capistrano and RVM for its deployment.
A good guide on how this was set up is [here](https://gorails.com/deploy/ubuntu/14.04).

It should be as easy as running the command:
`cap production deploy`

But you will also need the production secret key, right now you'll need to contact jimmyrocks for it. 

Once you find it, you can run the command:
`export SECRET_KEY_BASE="KEY GOES HERE"`
