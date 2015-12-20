CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "#{application_name} - Web ActiveMQ v#{cf_version}"

  # Parameters
  Parameter("EnvironmentType"){ Type 'String' }
  Parameter("EnvironmentName"){ Type 'String' }
  Parameter("VPC"){ Type 'String' }
  Parameter("StackOctet") { Type 'String' }
  Parameter("RouteTablePrivateA"){ Type 'String' }
  Parameter("RouteTablePrivateB"){ Type 'String' }
  Parameter("SubnetPublicA"){ Type 'String' }
  Parameter("SubnetPublicB"){ Type 'String' }
  Parameter("SecurityGroupBackplane"){ Type 'String' }
  Parameter("SecurityGroupOps"){ Type 'String' }
  Parameter("SecurityGroupDev"){ Type 'String' }

  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('ActiveMQAMI', amqAMI)

  Condition("ActiveMQHAA", FnEquals('true','true'))
  Condition("ActiveMQHAB", FnEquals(FnFindInMap('EnvironmentType', Ref('EnvironmentType'), 'AMQHA'), 'true'))

  availability_zones.each do |az|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", activemq["SubnetOctet#{az}"], ".0/24" ] ))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref( "AWS::Region" )) ))
      Property('Tags',[
        {
          Key: 'Name', Value: FnJoin( "", [ Ref('EnvironmentName'), "-ActiveMQ-private#{az}"])
        }
      ])
    }
  end

  rules = []

  Resource("SecurityGroupPrivate") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'ELB Access')
    Property('SecurityGroupIngress', [
      { 'IpProtocol' => 'tcp', 'FromPort' => '80', 'ToPort' => '80', 'CidrIp' => FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) },
      { 'IpProtocol' => 'tcp', 'FromPort' => '443', 'ToPort' => '443', 'CidrIp' => FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) }
    ])
  }

  availability_zones.each do |az|
    Resource("SubnetRouteTableAssociationPrivate#{az}") {
      Type 'AWS::EC2::SubnetRouteTableAssociation'
      Property('SubnetId', Ref("SubnetPrivate#{az}"))
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
    }
  end

  Resource("Role") {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      'Statement' => [
        'Effect' => 'Allow',
        'Principal' => { 'Service' => [ 'ec2.amazonaws.com' ] },
        'Action' => [ 'sts:AssumeRole' ]
      ]
    })
    Property('Path','/')
    Property('Policies', [
      {
        PolicyName: 'AttachNetworkInterface',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'ec2:DescribeNetworkInterfaces', 'ec2:AttachNetworkInterface' ],
              Resource: '*'
            }
          ]
        }
      },
      {
        'PolicyName' => 's3-list-buckets',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [ 's3:ListAllMyBuckets','s3:ListBucket'],
              'Resource' => 'arn:aws:s3:::*'
            }
          ]
        }
      },
      {
        'PolicyName' => 'chef-read-only',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [ 's3:Get*', 's3:List*' ],
              'Resource' => [ "arn:aws:s3:::#{source_bucket}'/chef","arn:aws:s3:::#{source_bucket}'/chef/*" ]
            }
          ]
        }
      },
      {
        'PolicyName' => 'containers-read-only',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [ 's3:Get*', 's3:List*' ],
              'Resource' => [ "arn:aws:s3:::#{source_bucket}'/containers","arn:aws:s3:::#{source_bucket}'/containers/*" ]
            }
          ]
        }
      },
      {
        'PolicyName' => 'ssh-key-download',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [ 's3:Get*', 's3:List*' ],
              'Resource' => [ "arn:aws:s3:::#{source_bucket}'/keys","arn:aws:s3:::#{source_bucket}'/keys/*" ]
            }
          ]
        }
      },
      {
        'PolicyName' => 'codedeploy-read-only',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [ 's3:Get*', 's3:List*' ],
              'Resource' => [ "arn:aws:s3:::#{source_bucket}'.au/codedeploy", "arn:aws:s3:::#{source_bucket}'/codedeploy/*" ]
            }
          ]
        }
      },
      {
        'PolicyName' => 'elb-asg-register-deregister',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [
                'ec2:Describe*',
                'elasticloadbalancing:Describe*',
                'elasticloadbalancing:DeregisterInstancesFromLoadBalancer',
                'elasticloadbalancing:RegisterInstancesWithLoadBalancer',
                'autoscaling:Describe*',
                'autoscaling:EnterStandby',
                'autoscaling:ExitStandby',
                'autoscaling:UpdateAutoScalingGroup'
              ],
              'Resource' => '*'
            }
          ]
        }
      },
      {
        'PolicyName' => 'packages-read-only',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [ 's3:Get*', 's3:List*' ],
              'Resource' => [ "arn:aws:s3:::#{source_bucket}'/packages", "arn:aws:s3:::#{source_bucket}'/packages/*" ]
            }
          ]
        }
      }

    ])
  }

  Resource("CodeDeployRole") {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      'Statement' => [
        'Effect' => 'Allow',
        'Principal' => {
          'Service' => [
            'codedeploy.ap-southeast-2.amazonaws.com'
          ]
        },
        'Action' => [ 'sts:AssumeRole' ]
      ]
    })
    Property('Path','/')
    Property('Policies', [
      'PolicyName' => 'CodeDeployRole',
      'PolicyDocument' => {
        'Statement' => [
          {
            'Effect' => 'Allow',
            'Action' => [
              'autoscaling:CompleteLifecycleAction',
              'autoscaling:DeleteLifecycleHook',
              'autoscaling:DescribeAutoScalingGroups',
              'autoscaling:DescribeLifecycleHooks',
              'autoscaling:PutLifecycleHook',
              'autoscaling:RecordLifecycleActionHeartbeat',
              'ec2:DescribeInstances',
              'ec2:DescribeInstanceStatus',
              'tag:GetTags',
              'tag:GetResources'
            ],
            'Resource' => '*'
          }
        ]
      }
    ])
  }

  Resource("InstanceProfile") {
    Type 'AWS::IAM::InstanceProfile'
    Property('Path','/')
    Property('Roles',[ Ref('Role') ])
  }

  LaunchConfiguration( :LaunchConfig ) {
    ImageId FnFindInMap('ActiveMQAMI',Ref('AWS::Region'),'ami')
    IamInstanceProfile Ref('InstanceProfile')
    KeyName FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'KeyName')
    SecurityGroups [ Ref('SecurityGroupBackplane'), Ref('SecurityGroupPrivate') ]
    InstanceType FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'AMQInstanceType')
    UserData FnBase64(FnJoin("",[
      "#!/bin/bash\n",
      "export NEW_HOSTNAME=", Ref('EnvironmentName') ,"-amqxx-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`\n",
      "echo \"NEW_HOSTNAME=$NEW_HOSTNAME\" \n",
      "hostname $NEW_HOSTNAME\n",
      "sed -i \"s/^\(HOSTNAME=\).*/\\1$NEW_HOSTNAME/\" /etc/sysconfig/network\n",
      "echo \"127.0.0.2 $NEW_HOSTNAME\" >> /etc/hosts\n",
      "aws ec2 attach-network-interface --instance-id $(curl http://169.254.169.254/2014-11-05/meta-data/instance-id -s) --network-interface-id $(aws ec2 describe-network-interfaces --query 'NetworkInterfaces[*].[NetworkInterfaceId]' --filter Name=tag:reservation,Values=", Ref('EnvironmentName'), "-activemq-$(curl http://169.254.169.254/2014-11-05/meta-data/placement/availability-zone/ -s | tail -c 1) --output text --region ", Ref('AWS::Region'), ") --device-index 1 --region ", Ref('AWS::Region'), "\n",
      "iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE\n",
      "GW=$(curl -s http://169.254.169.254/2014-11-05/meta-data/local-ipv4/ | cut -d '.' -f 1-3).1\n",
      "#route del -net 0.0.0.0 gw $GW netmask 0.0.0.0 dev eth0 metric 0\n",
      "#route add -net 0.0.0.0 gw $GW netmask 0.0.0.0 dev eth0 metric 10002\n",
      "/opt/#{no_spaces_client_name}/ec2_bootstrap ", Ref("AWS::Region"), " ", Ref('AWS::AccountId'), "\n"
    ]))
  }

  availability_zones.each do |az|
    AutoScalingGroup("AutoScaleGroup#{az}") {
      Condition("ActiveMQHA#{az}")
      UpdatePolicy("AutoScalingRollingUpdate", {
        "MinInstancesInService" => "0",
        "MaxBatchSize"          => "1",
      })
      VPCZoneIdentifier [ Ref("SubnetPrivate#{az}") ]
      LaunchConfigurationName Ref('LaunchConfig')
      HealthCheckGracePeriod '500'
      MinSize 1
      MaxSize 1
      HealthCheckType FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'AMQHealthCheckType')
      addTag("Name", FnJoin("",[Ref("EnvironmentName"),"-amq-#{az}-xx"]), true)
      addTag("Environment", Ref("EnvironmentName"), true)
      addTag("EnvironmentType", Ref("EnvironmentType"), true)
      addTag("Role", "amq", true)
    }

    Resource("ActiveMQENI#{az}"){
      Type "AWS::EC2::NetworkInterface"
      Condition("ActiveMQHA#{az}")
      Property("Description", "ActiveMQENI#{az}")
      Property("SourceDestCheck", "false")
      Property("GroupSet", [ Ref("SecurityGroupBackplane") ])
      Property("SubnetId", Ref("SubnetPrivate#{az}"))
      Property("PrivateIpAddress", FnJoin( "", [FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", activemq["SubnetOctet#{az}"], ".42" ]))
      Property('Tags',[
          {
            Key: 'Name', Value: FnJoin( "", [ Ref('EnvironmentName'), "-activemq-eni#{az}"])
          },
          {
            Key: 'Environment', Value: Ref("EnvironmentType")
          },
          {
            Key: "Role", Value: "activemq"
          },
          {
            Key: 'reservation',
            Value: FnJoin("",[ Ref('EnvironmentName'), "-activemq-#{az.downcase}"])
          }
      ])
    }

    Resource("ActiveMQ#{az}RecordSet") {
      Type 'AWS::Route53::RecordSet'
      Condition("ActiveMQHA#{az}")
      Property('HostedZoneName', FnJoin('', [ Ref('EnvironmentName'), '.', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix'), '.']))
      Property('Comment', "ActiveMQ#{az} Record Set")
      Property('Name', FnJoin('.', [ "amq#{az}", Ref('EnvironmentName'), FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix') ]))
      Property('Type', "A")
      Property('TTL', "60")
      Property('ResourceRecords', [ FnJoin( "", [FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", activemq["SubnetOctet#{az}"], ".42"] ) ] )
    }

  end


}
