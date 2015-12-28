require 'cfndsl'
require_relative 'lib/vpc'

CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "#{application_name} - VPC v#{cf_version}"

  # Parameters
  Parameter("EnvironmentType"){ Type 'String' }
  Parameter("EnvironmentName"){ Type 'String' }
  Parameter("StackOctet") { Type 'String' }

  availability_zones.each do |az|
  Parameter("Nat#{az}EIPAllocationId") { Type 'String' }
  end

  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])
  Mapping('NatAMI', natAMI)

  availability_zones.each do |az|
  Condition("Nat#{az}EIPRequired", FnEquals(Ref("Nat#{az}EIPAllocationId"), 'dynamic'))
  end

  # Resources
  Resource("VPC") {
    Type 'AWS::EC2::VPC'
    Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/", FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ))
    Property('EnableDnsSupport', true)
    Property('EnableDnsHostnames', true)
  }

  Resource("HostedZone") {
    Type 'AWS::Route53::HostedZone'
    Property('Name', FnJoin('.', [ Ref('EnvironmentName'), FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix') ]) )
}

  availability_zones.each do |az|
    Resource("SubnetPublic#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", vpc["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'SubnetMask') ] ))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref( "AWS::Region" )) ))
      Property('Tags',[
        {
          Key: 'Name', Value: FnJoin( "", [ Ref('EnvironmentName'), "-public#{az}"])
        }
      ])
    }
  end

  Resource("InternetGateway") {
    Type 'AWS::EC2::InternetGateway'
  }

  Resource("AttachGateway") {
    Type 'AWS::EC2::VPCGatewayAttachment'
    Property('VpcId', Ref('VPC'))
    Property('InternetGatewayId', Ref('InternetGateway'))
  }

  Resource("RouteTablePublic") {
    Type 'AWS::EC2::RouteTable'
    Property('VpcId', Ref('VPC'))
  }

  availability_zones.each do |az|
    Resource("RouteTablePrivate#{az}") {
      Type 'AWS::EC2::RouteTable'
      Property('VpcId', Ref('VPC'))
    }
  end

  availability_zones.each do |az|
    Resource("SubnetRouteTableAssociationPublic#{az}") {
      Type 'AWS::EC2::SubnetRouteTableAssociation'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('RouteTableId', Ref('RouteTablePublic'))
    }
  end

  Resource("PublicRouteOutToInternet") {
    Type 'AWS::EC2::Route'
    Property('RouteTableId', Ref("RouteTablePublic"))
    Property('DestinationCidrBlock', '0.0.0.0/0')
    Property('GatewayId',Ref("InternetGateway"))
  }

  Resource("PublicNetworkAcl") {
    Type 'AWS::EC2::NetworkAcl'
    Property('VpcId', Ref('VPC'))
  }

  # Name => RuleNumber, Protocol, RuleAction, Egress, CidrBlock, PortRange From, PortRange To
  acls = {
    InboundHTTPPublicNetworkAclEntry:       ['100','6','allow','false','0.0.0.0/0','80','80'],
    InboundHTTPSPublicNetworkAclEntry:      ['101','6','allow','false','0.0.0.0/0','443','443'],
    InboundSSHPublicNetworkAclEntry:        ['102','6','allow','false','0.0.0.0/0','22','22'],
    InboundNTPPublicNetworkAclEntry:        ['103','17','allow','true','0.0.0.0/0','123','123'],
    InboundEphemeralPublicNetworkAclEntry:  ['104','6','allow','false','0.0.0.0/0','1024','65535'],
    OutboundNetworkAclEntry:                ['105','-1','allow','true','0.0.0.0/0','0','65535'],
    InboundSMTPPrivateNetworkAclEntry:      ['106','6','allow','false','10.0.0.0/8','25','25']
  }
  acls.each do |alcName,alcProperties|
    Resource(alcName) {
      Type 'AWS::EC2::NetworkAclEntry'
      Property('NetworkAclId', Ref('PublicNetworkAcl'))
      Property('RuleNumber', alcProperties[0])
      Property('Protocol', alcProperties[1])
      Property('RuleAction', alcProperties[2])
      Property('Egress', alcProperties[3])
      Property('CidrBlock', alcProperties[4])
      Property('PortRange',{
        From: alcProperties[5],
        To: alcProperties[6]
      })
    }
  end

  availability_zones.each do |az|
    Resource("SubnetNetworkAclAssociationPublic#{az}") {
      Type 'AWS::EC2::SubnetNetworkAclAssociation'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('NetworkAclId', Ref('PublicNetworkAcl'))
    }
  end

  Resource("DHCPOptionSet") {
    Type 'AWS::EC2::DHCPOptions'
    Property('DomainName', FnJoin('.', [ Ref('EnvironmentName'), FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix') ]))
    Property('DomainNameServers', ['AmazonProvidedDNS'])
  }

  Resource("DHCPOptionsAssociation") {
    Type 'AWS::EC2::VPCDHCPOptionsAssociation'
    Property('VpcId', Ref('VPC'))
    Property('DhcpOptionsId', Ref('DHCPOptionSet'))
  }

  rules = []
  opsAccess.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '5432', ToPort: '5432', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '8161', ToPort: '8161', CidrIp: ip }
  end

  Resource("SecurityGroupOps") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Ops External Access')
    Property('SecurityGroupIngress', rules)
  }

  rules = []
  devAccess.each do |ip|
    rules << { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '5432', ToPort: '5432', CidrIp: ip }
    rules << { IpProtocol: 'tcp', FromPort: '8161', ToPort: '8161', CidrIp: ip }
  end

  Resource("SecurityGroupDev") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Dev Team Access')
    Property('SecurityGroupIngress', rules)
  }

  Resource("SecurityGroupBackplane") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Backplane SG')
    Property('SecurityGroupIngress', [
      { IpProtocol: 'tcp', FromPort: '22', ToPort: '22', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/",FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '80', ToPort: '80', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/",FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '443', ToPort: '443', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/",FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '61616', ToPort: '61616', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/",FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '8161', ToPort: '8161', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/",FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '25', ToPort: '25', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/",FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) },
      { IpProtocol: 'udp', FromPort: '123', ToPort: '123', CidrIp: FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/",FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) },
      { IpProtocol: 'tcp', FromPort: '5666', ToPort: '5666', CidrIp: monitoringSubnet },
    ])
  }

  Resource("SecurityGroupInternalNat") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Internal NAT SG')
    Property('SecurityGroupIngress', [
      { IpProtocol: 'tcp', FromPort: '1', ToPort: '65535', CidrIp: FnJoin( "", [FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".0.0/", FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'StackMask') ] ) }
    ])
  }

  Resource("Role") {
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      Statement: [
        Effect: 'Allow',
        Principal: { Service: [ 'ec2.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      ]
    })
    Property('Path','/')
    Property('Policies', [
      {
        PolicyName: 'read-only',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'ec2:Describe*', 's3:Get*', 's3:List*'],
              Resource: '*'
            }
          ]
        }
      },
      {
        PolicyName: 'ssh-key-upload',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 's3:PutObject','s3:PutObject*' ],
              Resource: "arn:aws:s3:::#{source_bucket}/keys/*"
            }
          ]
        }
      },
      {
        PolicyName: 'AttachNetworkInterface',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [ 'ec2:DescribeNetworkInterfaces', 'ec2:AttachNetworkInterface', 'ec2:DetachNetworkInterface' ],
              Resource: '*'
            }
          ]
        }
      },
      {
        PolicyName: 'describe-ec2-autoscaling',
        PolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'ec2:Describe*', 'autoscaling:Describe*' ],
              Resource: '*'
            }
          ]
        }
      }
    ])
  }

  Resource("InstanceProfile") {
    Type 'AWS::IAM::InstanceProfile'
    Property('Path','/')
    Property('Roles',[ Ref('Role') ])
  }

  availability_zones.each do |az|
    Resource("NatIPAddress#{az}") {
      Type 'AWS::EC2::EIP'
      Condition("Nat#{az}EIPRequired")
      Property('Domain', 'vpc')
    }
  end

  availability_zones.each do |az|
    Resource("NetworkInterface#{az}") {
      Type 'AWS::EC2::NetworkInterface'
      Property('SubnetId', Ref("SubnetPublic#{az}"))
      Property('SourceDestCheck', false)
      Property('GroupSet', [
        Ref('SecurityGroupInternalNat'),
        Ref('SecurityGroupOps'),
        Ref('SecurityGroupBackplane'),
        Ref('SecurityGroupDev')
      ])
      Property('Tags',[
        {
          'Key' => 'reservation',
          'Value' => FnJoin("",[ Ref('EnvironmentName'), "-nat-#{az.downcase}"])
        }
      ])
    }
  end

  availability_zones.each do |az|
    Resource("EIPAssociation#{az}") {
      Type 'AWS::EC2::EIPAssociation'
      Property('AllocationId', FnIf("Nat#{az}EIPRequired",
        FnGetAtt("NatIPAddress#{az}",'AllocationId'),
        Ref("Nat#{az}EIPAllocationId")
      ))
      Property('NetworkInterfaceId', Ref("NetworkInterface#{az}"))
    }
  end

  availability_zones.each do |az|
    Resource("RouteOutToInternet#{az}") {
      Type 'AWS::EC2::Route'
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
      Property('DestinationCidrBlock', '0.0.0.0/0')
      Property('NetworkInterfaceId',Ref("NetworkInterface#{az}"))
    }
  end

  availability_zones.each do |az|
    Resource("LaunchConfig#{az}") {
      Type 'AWS::AutoScaling::LaunchConfiguration'
      Property('ImageId', FnFindInMap('NatAMI',Ref('AWS::Region'),'ami') )
      Property('AssociatePublicIpAddress',true)
      Property('IamInstanceProfile', Ref('InstanceProfile'))
      Property('KeyName', FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'KeyName') )
      Property('SecurityGroups',[ Ref('SecurityGroupBackplane'),Ref('SecurityGroupInternalNat'),Ref('SecurityGroupOps') ])
      Property('InstanceType', FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NatInstanceType'))
      Property('UserData', FnBase64(FnJoin("",[
        "#!/bin/bash\n",
        "export ENI_A=", Ref("NetworkInterfaceA"), "\n",
        "export ENI_B=", Ref("NetworkInterfaceB"), "\n",
        "export NEW_HOSTNAME=", Ref('EnvironmentName') ,"-nat-#{az}-xx-`/opt/aws/bin/ec2-metadata --instance-id|/usr/bin/awk '{print $2}'`\n",
        "echo \"NEW_HOSTNAME=$NEW_HOSTNAME\" \n",
        "hostname $NEW_HOSTNAME\n",
        "sed -i \"s/^\(HOSTNAME=\).*/\\1$NEW_HOSTNAME/\" /etc/sysconfig/network\n",
        "ATTACH_ID=`aws ec2 describe-network-interfaces --query 'NetworkInterfaces[*].[Attachment][*][*].AttachmentId' --filter Name=network-interface-id,Values='", Ref("NetworkInterface#{az}") ,"' --region ap-southeast-2 --output text`\n",
        "aws ec2 detach-network-interface --attachment-id $ATTACH_ID  --region", Ref("AWS::Region") ," --force \n",
        "aws ec2 attach-network-interface --instance-id $(curl http://169.254.169.254/2014-11-05/meta-data/instance-id -s) --network-interface-id ", Ref("NetworkInterface#{az}") ," --device-index 1 --region ap-southeast-2 \n",
        "sysctl -w net.ipv4.ip_forward=1\n",
        "iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE\n",
        "GW=$(curl -s http://169.254.169.254/2014-11-05/meta-data/local-ipv4/ | cut -d '.' -f 1-3).1\n",
        "route del -net 0.0.0.0 gw $GW netmask 0.0.0.0 dev eth0 metric 0\n",
        "route add -net 0.0.0.0 gw $GW netmask 0.0.0.0 dev eth0 metric 10002\n",
        "/opt/client/ec2_bootstrap ", Ref("AWS::Region"), "\n",
        "DB=`host db | awk '/has address/ { print $4 }'`\n",
        "IP=`ifconfig eth1 | awk '/inet addr/{print substr($2,6)}'`\n",
        "iptables -t nat -A PREROUTING -p TCP --dport 5432 -j DNAT --to-destination $DB:5432\n",
        "iptables -t nat -A POSTROUTING -p tcp --dport 5432 -j SNAT --to-source $IP\n",
        "AMQA=", FnJoin( "", [FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", activemq["SubnetOctetA"], ".42"] ), "\n",
        "iptables -t nat -A PREROUTING -p TCP --dport 8161 -j DNAT --to-destination $AMQA:8161\n",
        "iptables -t nat -A POSTROUTING -p tcp --dport 8161 -j SNAT --to-source $IP\n",
        "iptables -t nat -L\n",
        "echo 'done!!!!'\n"
      ])))
    }
  end

  availability_zones.each do |az|
    AutoScalingGroup("AutoScaleGroup#{az}") {
      UpdatePolicy("AutoScalingRollingUpdate", {
        "MinInstancesInService" => "0",
        "MaxBatchSize"          => "1",
      })
      LaunchConfigurationName Ref("LaunchConfig#{az}")
      HealthCheckGracePeriod '500'
      MinSize 1
      MaxSize 1
      VPCZoneIdentifier [ Ref("SubnetPublic#{az}") ]
      addTag("Name", FnJoin("",[Ref('EnvironmentName'), "-nat-#{az.downcase}"]), true)
      addTag("Environment",Ref('EnvironmentName'), true)
      addTag("EnvironmentType", Ref('EnvironmentType'), true)
      addTag("Role", "nat", true)
    }
  end

  Resource("HostedZone") {
    Type 'AWS::Route53::HostedZone'
    Property('Name', FnJoin('.', [ Ref('EnvironmentName'), FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix') ]) )
  }

  availability_zones.each do |az|
    Resource("Nat#{az}RecordSet") {
      Type 'AWS::Route53::RecordSet'
      Condition("Nat#{az}EIPRequired")
      DependsOn ["NetworkInterface#{az}"]
      Property('HostedZoneId', Ref('HostedZone') )
      Property('Comment', "NAT Public Record Set")
      Property('Name', FnJoin('.', [ "nat#{az}", Ref('EnvironmentName'), FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix') ]))
      Property('Type', "A")
      Property('TTL', "60")
      Property('ResourceRecords', [ Ref("NatIPAddress#{az}") ] )
    }
  end

  Resource("MailRecordSet") {
    Type 'AWS::Route53::RecordSet'
    Property('HostedZoneId', Ref('HostedZone') )
    Property('Comment', "Mail DNS")
    Property('Name', FnJoin('.', [ "mail", Ref('EnvironmentName'), FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix') ]))
    Property('Type', "A")
    Property('TTL', "60")
    Property('ResourceRecords', [
      FnGetAtt('NetworkInterfaceA', 'PrimaryPrivateIpAddress'),
      FnGetAtt('NetworkInterfaceB', 'PrimaryPrivateIpAddress')
    ])
  }

  Output("VPCId") {
    Value(Ref('VPC'))
  }

  Output("StackOctet") {
    Value(Ref('StackOctet'))
  }

  availability_zones.each do |az|
    Output("RouteTablePrivate#{az}") {
      Value(Ref("RouteTablePrivate#{az}"))
    }
  end

  availability_zones.each do |az|
    Output("SubnetPublic#{az}") {
      Value(Ref("SubnetPublic#{az}"))
    }
  end

  Output("SecurityGroupBackplane") {
    Value(Ref('SecurityGroupBackplane'))
  }

  Output("SecurityGroupOps") {
    Value(Ref('SecurityGroupOps'))
  }

  Output("SecurityGroupDev") {
    Value(Ref('SecurityGroupDev'))
  }

}
