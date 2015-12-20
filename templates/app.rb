CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "#{application_name} - Web App v#{cf_version}"

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
  Parameter("CertName"){ Type 'String' }


  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('AppAMI', appAMI)

  availability_zones.each do |az|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", app["SubnetOctet#{az}"], ".0/24" ] ))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref( "AWS::Region" )) ))
      Property('Tags',[
        {
          Key: 'Name', Value: FnJoin( "", [ Ref('EnvironmentName'), "-app-private#{az}"])
        }
      ])
    }
  end

  rules = []
  publicAccess.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
  end

  Resource("SecurityGroupPublic") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Public Access')
    Property('SecurityGroupIngress', rules)
  }

  Resource("SecurityGroupPrivate") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'ELB Access')
    Property('SecurityGroupIngress', [
      { 'IpProtocol' => 'tcp', 'FromPort' => '80', 'ToPort' => '80', 'CidrIp' => FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) },
      { 'IpProtocol' => 'tcp', 'FromPort' => '8080', 'ToPort' => '8080', 'CidrIp' => FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) },
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
        'PolicyName' => 'container-read-only',
        'PolicyDocument' => {
          'Statement' => [
            {
              'Effect' => 'Allow',
              'Action' => [ 's3:Get*', 's3:List*' ],
              'Resource' => [ "arn:aws:s3:::#{source_bucket}'/containers", "arn:aws:s3:::#{source_bucket}'/codedeploy/*" ]
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
    ImageId FnFindInMap('AppAMI',Ref('AWS::Region'),'ami')
    IamInstanceProfile Ref('InstanceProfile')
    KeyName FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'KeyName')
    SecurityGroups [ Ref('SecurityGroupBackplane'), Ref('SecurityGroupPrivate') ]
    InstanceType FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'AppInstanceType')
    UserData FnBase64(FnJoin("",[
      "#!/bin/bash\n",
      "hostname ", Ref('EnvironmentName') ,"-appxx-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`\n",
      "sed '/HOSTNAME/d' /etc/sysconfig/network > /tmp/network && mv -f /tmp/network /etc/sysconfig/network && echo \"HOSTNAME=", Ref('EnvironmentName') ,"-appxx-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`\" >>/etc/sysconfig/network && /etc/init.d/network restart\n",
      "/opt/#{no_spaces_client_name}/ec2_bootstrap ", Ref("AWS::Region"), " ", Ref('AWS::AccountId'), "\n"
    ]))
  }

  AutoScalingGroup("AutoScaleGroup") {
    UpdatePolicy("AutoScalingRollingUpdate", {
      "MinInstancesInService" => "0",
      "MaxBatchSize"          => "1",
    })
    AvailabilityZones [
      FnSelect('0',FnGetAZs(Ref('AWS::Region'))),
      FnSelect('1',FnGetAZs(Ref('AWS::Region')))
    ]
    LaunchConfigurationName Ref('LaunchConfig')
    LoadBalancerNames [ Ref('ElasticLoadBalancer') ]
    HealthCheckGracePeriod '500'
    HealthCheckType FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'AppHealthCheckType')
    MinSize FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'AppMinSize')
    MaxSize FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'AppMaxSize')
    VPCZoneIdentifier [ Ref('SubnetPrivateA'),Ref('SubnetPrivateB') ]
    addTag("Name", FnJoin("",[Ref("EnvironmentName"),"-app-xx"]), true)
    addTag("Environment", Ref("EnvironmentName"), true)
    addTag("EnvironmentType", Ref("EnvironmentType"), true)
    addTag("Role", "app", true)
  }

  Resource("ElasticLoadBalancer") {
    Type 'AWS::ElasticLoadBalancing::LoadBalancer'
    Property('Listeners', [
          { 'LoadBalancerPort' => '80', 'InstancePort' => '8080', 'Protocol' => 'HTTP' },
          { 'LoadBalancerPort' => '443', 'InstancePort' => '8080', 'Protocol' => 'HTTPS', 'SSLCertificateId' => FnJoin('',['arn:aws:iam::', Ref('AWS::AccountId'), ':server-certificate/', Ref('CertName')]) }
      ]
    )
    Property('HealthCheck', {
      'Target' => 'TCP:8080',
      'HealthyThreshold' => '3',
      'UnhealthyThreshold' => '2',
      'Interval' => '15',
      'Timeout' => '5'
    })
    Property('ConnectionDrainingPolicy', {
      'Enabled' => 'true',
      'Timeout' => '300'
    })
    Property('CrossZone',true)
    Property('SecurityGroups',[
      Ref('SecurityGroupPublic'),
      Ref('SecurityGroupOps'),
      Ref('SecurityGroupDev')
    ])
    Property('Subnets',[
      Ref('SubnetPublicA'),Ref('SubnetPublicB')
    ])
    Property('LoadBalancerName',FnJoin('', [ Ref('EnvironmentName'), '-app' ]))
  }

  Resource("LoadBalancerRecord") {
    Type 'AWS::Route53::RecordSet'
    Property('HostedZoneName', FnJoin('', [ Ref('EnvironmentName'), '.', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix'), '.']))
    Property('Name', FnJoin('', [Ref('EnvironmentName'), '.', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix'), '.']))
    Property('Type','A')
    Property('AliasTarget', {
      'DNSName' => FnGetAtt('ElasticLoadBalancer','DNSName'),
      'HostedZoneId' => FnGetAtt('ElasticLoadBalancer','CanonicalHostedZoneNameID')
    })
  }

  Resource("ScaleUpPolicy") {
    Type 'AWS::AutoScaling::ScalingPolicy'
    Property('AdjustmentType', 'ChangeInCapacity')
    Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
    Property('Cooldown','300')
    Property('ScalingAdjustment', '1')
  }

  Resource("ScaleDownPolicy") {
    Type 'AWS::AutoScaling::ScalingPolicy'
    Property('AdjustmentType', 'ChangeInCapacity')
    Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
    Property('Cooldown','300')
    Property('ScalingAdjustment', '-1')
  }

  Resource("CPUAlarmHigh") {
    Type 'AWS::CloudWatch::Alarm'
    Property('AlarmDescription', 'Scale-up if CPU > 60% for 2 minutes')
    Property('MetricName','CPUUtilization')
    Property('Namespace','AWS/EC2')
    Property('Statistic', 'Average')
    Property('Period', '60')
    Property('EvaluationPeriods', '2')
    Property('Threshold', '60')
    Property('AlarmActions', [ Ref('ScaleUpPolicy') ])
    Property('Dimensions', [
      {
        'Name' => 'AutoScalingGroupName',
        'Value' => Ref('AutoScaleGroup')
      }
    ])
    Property('ComparisonOperator', 'GreaterThanThreshold')
  }

  Resource("CPUAlarmLow") {
    Type 'AWS::CloudWatch::Alarm'
    Property('AlarmDescription', 'Scale-up if CPU < 40% for 4 minutes')
    Property('MetricName','CPUUtilization')
    Property('Namespace','AWS/EC2')
    Property('Statistic', 'Average')
    Property('Period', '60')
    Property('EvaluationPeriods', '4')
    Property('Threshold', '30')
    Property('AlarmActions', [ Ref('ScaleDownPolicy') ])
    Property('Dimensions', [
      {
        'Name' => 'AutoScalingGroupName',
        'Value' => Ref('AutoScaleGroup')
      }
    ])
    Property('ComparisonOperator', 'LessThanThreshold')
  }

}
