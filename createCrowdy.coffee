AWS = require 'aws-sdk'
_ = require 'lodash'
async = require 'async'
config = require './config'

ec2 = new AWS.EC2({reqion:config.region})
elb = new AWS.ELB({region:config.region})

main = () ->
  async.waterfall([
    getNewestAMI,
    startAMI,
    prepNewInstance
    # Attach EBS
    # Associate Elastic IP
    # Add to Load Balancer
  ], (err, result) ->
    if err then return console.error err
    console.log result
)

getNewestAMI = (callback)->
  # create the AWS.Request object
  ec2.describeImages(
    {
      Owners:['self'],
      Filters:[
        { Name: 'tag:purpose', Values: [config.purpose] }
      ]
    },
    (err,resp) ->
      if err then return callback(err)
      sorted = _.sortBy(resp.Images, (image) ->
        return new Date(image.CreationDate)
      ).reverse()
      callback(err, sorted[0])
  )

startAMI = (image, callback) ->
  console.log "Starting Instance from AMI #{image.ImageId}"
  ec2.runInstances(
    {
      DryRun: false
      ImageId:image.ImageId
      MinCount:1
      MaxCount:1
      KeyName: config.KeyName
      SecurityGroupIds:config.SecurityGroupIds
      InstanceType: config.InstanceType
      SubnetId: config.SubnetId
    },
    (err, results) ->
      if err then return callback(err)
      # Currently only support a use case of a single instance
      # though a foreach would be trivial to add
      if results.Instances and results.Instances.length is 1
        console.log "Created instance #{results.Instances[0].InstanceId}"
        console.log results
        callback(null, results.Instances[0])
      else
        callback(results)
  )

prepNewInstance = (instance, callback) ->
  console.log "Waiting for instance"
  # Wait for the instance to run
  ec2.waitFor('instanceRunning',
    {InstanceIds:[instance.InstanceId]},
    (err, data) ->
      if err then return callback(err)
      console.log "#{instance.InstanceId} is ready. Next: Tags, ELB, Elastic IP"
      async.parallel([
        # Tag Instance
        ((cb) ->
          ec2.createTags({
              Resources:[instance.InstanceId]
              Tags:[{Key:'purpose', Value:config.purpose}]
            },
            cb
          )
        ),
        # Add instance to loadbalancer
        ((cb) ->
          if not config.LoadBalancerName
            console.log "No Load Balancer specified in config, skipping."
            cb(null)
          elb.registerInstancesWithLoadBalancer({
              Instances:[{InstanceId:instance.InstanceId}]
              LoadBalancerName:config.LoadBalancerName
            },
            cb
          )
        ),
        # Associate my preferred Elastic IP with new instance
        ((cb) ->
          console.log "No Elastic IP Allocation Id in config, skipping."
           ec2.associateAddress({
              InstanceId:instance.InstanceId
              AllocationId:config.ElasticIPAllocationId
              # If another instance has this IP, rip it from its cold dead hands
              AllowReassociation: true
            },
            cb
          )
        )
      ],
      callback
      )
  )

main()
