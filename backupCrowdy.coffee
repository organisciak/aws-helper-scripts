AWS = require 'aws-sdk'
_ = require 'lodash'
async = require 'async'

config = require './config.json'

ec2 = new AWS.EC2({region:config.region})
elb = new AWS.ELB({region:config.region})

main = () ->
  async.waterfall([
    getNewestInstance,
    createAMI
    prepNewImage
  ], (err, result) ->
    if err then return console.error err
    console.log result
)

getNewestInstance = (callback)->
  # create the AWS.Request object
  ec2.describeInstances(
    {
      Filters:[
        { Name: 'tag:purpose', Values: [config.purpose] }
      ]
    },
    (err,resp) ->
      if err then return callback(err)
      sorted = _.sortBy(resp.Reservations[0].Instances, (instance) ->
        return new Date(instance.LaunchTime)
      ).reverse()
      callback(err, sorted[0])
  )

createAMI = (instance, callback) ->
  console.log "Saving AMI from Instance #{instance.InstanceId}"
  ec2.createImage(
    {
      DryRun: false
      InstanceId:instance.InstanceId
      Name:"#{config.purpose}-#{(new Date()).getTime()}"
    },
    (err, results) ->
      if err then return callback(err)
      console.log "Created image #{results.ImageId}"
      console.log "[Blocking] Waiting for image to be available."
      ec2.waitFor('imageAvailable',
        {ImageIds:[results.ImageId], Owners:['self']},
        (err, data) ->
          callback(err, results)
      )
  )

prepNewImage = (image, callback) ->
  async.parallel([
    # Tag Instance
    ((cb) ->
      console.log "Tagging image #{image.ImageId}"
      ec2.createTags({
          Resources:[image.ImageId]
          Tags:[{Key:'purpose', Value: config.purpose}]
        },
        cb
      )
    )
  ],
  callback
  )

main()
