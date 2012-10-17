Singleton = require './singleton'
Config = require './config'
Logger = require './logger'
redis = require 'redis'
async = require 'async'

###*
 * Redis utility wrapper for the iOS-ota service.
###
class RedisUtility
  constructor: (port, host, options, @prefix="ios-ota-") ->
    @redis = redis.createClient(port, host, options)
    @modify_redis()
    return @redis

  # Adds some sugar to our redis client.
  modify_redis: () =>

    ###*
     * Returns the key, prefixed.
     * @param {String} (key) The key to prefix
     * @return {String} The key prefixed with the class prefix
    ###
    @redis.prefix = (key) =>
      ''.concat(@prefix, key)

    ###*
     * Returns the list of users.
     * @param {Function} (fn) The callback function
    ###
    @redis.get_users = (fn) =>
      @redis.get(@redis.prefix('users'), fn)

    ###*
     * Returns the full user hash.
     * @param {String} (username) The username to retrieve all keys for
     * @param {Function} (fn) The callback function
    ###
    @redis.get_user = (username, fn) =>
      @redis.hgetall(''.concat(@redis.prefix('user'), '-', username), fn)

    ###*
     * Returns the user's encrypted secret.
     * @param {String} (username) The username to retrieve the secret for
     * @param {Function} (fn) The callback function
    ###
    @redis.get_user_secret = (username, fn) =>
      @redis.hget(''.concat(
        @redis.prefix('user'), '-', username), 'secret', fn)

    ###*
     * Adds or updates a user with the given user object.
     * @param {Object} (user) The user object hash to create or update
     * @param {Function} (fn) The callback function
    ###
    @redis.add_or_update_user = (user, fn) =>
      user_prefix = ''.concat(@redis.prefix('user'), '-', user.username)
      # hset_cmd = []
      # hset_cmd.push(user_prefix)
      # for key in Object.keys(user)
      #   hset_cmd.push(key)
      #   hset_cmd.push(user[key])
      # console.log(hset_cmd)
      @redis.hmset(user_prefix, user, fn)

###*
 * Redis utility wrapper that acts as a singleton.
###
class RedisUtils extends Singleton
  constructor: ->
    @config = Config.get()
    @logger = Logger.get()
    @redis = new RedisUtility(
      @config.get("redis_port"),@config.get("redis_host") )

    @redis.on "error", (err) =>
      @logger.error ''.concat("Error connecting to redis://"
        @config.get('redis_host'), ':', @config.get('redis_port'))
      process.exit(1)

    return @redis

module.exports = RedisUtils