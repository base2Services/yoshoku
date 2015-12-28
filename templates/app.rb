require_relative "lib/standard"
CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "#{application_name} - Web App v#{cf_version}"

  # Parameters
  params = [
    { :name => "EnvironmentType", :type =>  'String' },
    { :name => "EnvironmentName", :type =>  'String' },
    { :name => "VPC", :type =>  'String' },
    { :name => "StackOctet", :type =>  'String' },
    { :name => "RouteTablePrivateA", :type =>  'String' },
    { :name => "RouteTablePrivateB", :type =>  'String' },
    { :name => "SubnetPublicA", :type =>  'String' },
    { :name => "SubnetPublicB", :type =>  'String' },
    { :name => "SecurityGroupBackplane", :type =>  'String' },
    { :name => "SecurityGroupOps", :type =>  'String' },
    { :name => "SecurityGroupDev", :type =>  'String' },
    { :name => "CertName", :type =>  'String' },
    { :name => "RoleName", :type => 'String' }
  ]
  parameters(params)

  # Global mappings
  maps = [
    { :name => 'EnvironmentType', :mapping => Mappings['EnvironmentType']},
    { :name => 'AppAMI', :mapping => appAMI}
  ]
  do_mappings(maps)

  azs = {}
  availability_zones.each do |az|
    azs[az] = {:az_id => azId[az], :range => app["SubnetOctet#{az}"] }
  end
  do_azs(azs)

  public_rules = []
  publicAccess.each do |ip|
    public_rules << { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: ip }
    public_rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
  end
  vpc_security_group("SecurityGroupPublic", 'Public Access', public_rules)

  private_rules =[
    { 'IpProtocol' => 'tcp', 'FromPort' => '80', 'ToPort' => '80', 'CidrIp' => FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) },
    { 'IpProtocol' => 'tcp', 'FromPort' => '8080', 'ToPort' => '8080', 'CidrIp' => FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) },
    { 'IpProtocol' => 'tcp', 'FromPort' => '443', 'ToPort' => '443', 'CidrIp' => FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) }
  ]
  vpc_security_group("SecurityGroupPrivate", 'ELB Access', private_rules)

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

  launch_configuration('AppAMI', ['SecurityGroupBackplane', 'SecurityGroupPrivate'], 'AppInstanceType', "/opt/#{no_spaces_client_name}/ec2_bootstrap" )

  auto_scaling_group("0", azs, 'LaunchConfig', 'ElasticLoadBalancer', 'AppHealthCheckType', 'AppMinSize', 'AppMinSize')


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
