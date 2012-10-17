Logger = require './logger'
Config = require './config'
restify = require 'restify'
{Identity, generate_identity} = require './identity'
RedisUtils = require './redisutils'
bcrypt = require 'bcrypt'
require('pkginfo')(module, 'name', 'version')

fs = require 'fs'
formidable = require 'formidable'

###*
 * The iOS-ota webserver command line interface class.
###
class WebServer
  constructor: (@port=8080) ->
    @config = Config.get()
    @logger = Logger.get()
    @identity = Identity.get()
    @redis = RedisUtils.get()
    @app = restify.createServer()
    @app.use(restify.bodyParser({ mapParams: true }))
    @setup_routing()
    @app.listen(@port)
    @logger.info "Webserver is up at: http://0.0.0.0:#{@port}"

  # Sets up the webserver routing.
  setup_routing: () =>

    # Returns the base name and version of the app.
    @app.get '/', (req, res, next) =>
      res.json 200, 
        name: exports.name,
        version: exports.version

    # Silence favicon requests.
    @app.get '/favicon.ico', (req, res, next) =>
      res.json 404,
        code: 404,
        message: "No favicon exists."

    # Returns the current list of users.
    @app.get '/users', (req, res, next) =>
      @redis.get_users (err, reply) ->
        if err
          return res.json 500,
            message: reply
        return res.json 200,
          users: if reply then reply else []

    # Creates or updates a user. (Requires Auth)
    @app.post '/users', (req, res, next) =>
      @authenticate req, (err, reply) =>
        if err
          return res.json reply.code,
            code: reply.code
            message: reply.message

        user = reply.user
        if user.username == "admin"
          return res.json 403,
            code: 403,
            message: "Unable to modify administrative user."

        if !reply.admin
          return res.json 401,
            code: 401,
            message: "Only administrators are allowed to modify accounts."

        fs.mkdir [@config.get('repository'), user.username].join('/'),
          () =>
            bcrypt.genSalt 10, (err, salt) =>
              if err
                return res.json 500,
                  code: 500,
                  message: "Error creating bcrypt salt."

              bcrypt.hash user.secret, salt, (error, hash) =>
                if error
                  return res.json 500,
                    code: 500,
                    message: "Error creating bcrypt hash."
                user.secret = hash
                @redis.add_or_update_user user, (err, reply) =>
                  if err
                    return res.json 500,
                      code: 500,
                      message: "Error updating user: " + user.username
                  return res.json 200
                    message: "Successfully updated: " + user.username

    # Deletes a user. (Requires Auth)
    @app.del '/users', (req, res, next) =>
      res.json 501,
        code: 501,
        message: "Restify current doesn't support parsing body params."

    # Returns the user-specific info.
    @app.get '/:user', (req, res, next) =>
      location = [req.params.user]
      name = location.join('/')
      location.unshift(@config.get('repository'))
      fs.readdir location.join('/'),
        (err, reply) =>
          if err
            return res.json 404,
              code: 404,
              user: req.params.user,
              message: ''.concat(
                "The user ", req.params.user, " does not exist.")
          return res.json 200,
            user: req.params.user
            apps: if reply then reply else []

    # Lists all of the branches for a specified user/application.
    @app.get '/:user/:app/branches', (req, res, next) =>
      location = [req.params.user, req.params.app, 'branches']
      name = location.join('/')
      location.unshift(@config.get('repository'))
      fs.readdir location.join('/'),
        (err, reply) =>
          console.log(err)
          console.log(reply)
          return res.json 200,
            mesasge: "BRANCHES BIATCH"

    # Lists all of the tags for a specified user/application.
    @app.get '/:user/:app/tags', (req, res) =>
      location = [req.params.user, req.params.app, 'tags']
      res.json 200,
        name: [req.params.user, req.params.app, 'tags'].join('/'),
        tags: fs.readdirSync

    # Posts new files to a specified user/application.
    @app.post '/:user/:app/branches', (req, res) ->
      location = [req.params.user, req.params.app, 'branches']
      @logger.info req
      form = formidable.IncomingForm()
      form.parse req, (err, fields, files) ->
        res.json 200,
          message: "Recieved Upload",
          fields: fields,
          files: files

    # Posts new tags to a specified user/application.
    @app.post '/:user/:app/tags', (req, res) ->
      location = [req.params.user, req.params.app, 'tags']
      @logger.info req
      form = formidable.IncomingForm()
      form.parse req, (err, fields, files) ->
        res.json 200,
          message: "Recieved Upload",
          fields: fields,
          files: files

  ###*
   * Authenticates the user.
   * @param {Object} (req) The restify request object
   * @param {Function} (fn) The callback function
  ###
  authenticate: (req, fn) =>
    err = false
    credentials =
      username: req.params.username
      secret: req.params.secret
    user = req.params.user

    if !credentials.username
      err = true
      reply =
        code: 401,
        message: "Unauthorized: No username parameter was provided."

    if !credentials.secret
      err = true
      reply =
        code: 401,
        message: "Unauthorized: No secret parameter was provided."

    if credentials.username == "admin"
      if credentials.secret != @config.get('admin_secret')
        err = true
        reply =
          code: 401,
          message: "Unauthorized: Invalid authentication secret."
      else
        reply =
          admin: true
          user: user
      return fn(err, reply)
    else
      @redis.check_login credentials, (err, authenticated) =>
        if authenticated
          reply =
            admin: false
            user: authenticated
        else
          err = true
          reply =
            code: 401,
            message: "Unauthorized: Invalid authentication secret."
        return fn(err, reply)

module.exports = WebServer
