require 'cfndsl'

CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "#{application_name} - Cache v#{cf_version}"

  # Parameters
  Parameter("EnvironmentType"){ Type 'String' }
  Parameter("EnvironmentName"){ Type 'String' }
  Parameter("VPC"){ Type 'String' }
  Parameter("StackOctet") { Type 'String' }
  Parameter("RouteTablePrivateA"){ Type 'String' }
  Parameter("RouteTablePrivateB"){ Type 'String' }
  Parameter("SecurityGroupBackplane"){ Type 'String' }

  # Global mappings
  Mapping('EnvironmentType', Mappings['EnvironmentType'])

  # Conditions
  Condition('IsProduction', FnEquals(Ref('EnvironmentType'), 'production'))

  availability_zones.each do |az|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", cache["SubnetOctet#{az}"], ".0/", FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'SubnetMask') ] ))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref( "AWS::Region" )) ))
    }
  end

  Resource("SecurityGroupCache") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'Cache Access')
    Property('SecurityGroupIngress', [
      { IpProtocol: 'tcp', FromPort: '6379', ToPort: '6379', CidrIp: FnJoin( "", [FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".", cache['SubnetOctetA'], ".0/24" ] ) },
      { IpProtocol: 'tcp', FromPort: '6379', ToPort: '6379', CidrIp: FnJoin( "", [FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".", cache['SubnetOctetB'], ".0/24" ] ) },
      { IpProtocol: 'tcp', FromPort: '6379', ToPort: '6379', CidrIp: FnJoin( "", [FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".", app['SubnetOctetA'], ".0/24" ] ) },
      { IpProtocol: 'tcp', FromPort: '6379', ToPort: '6379', CidrIp: FnJoin( "", [FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'NetworkPrefix'),".", Ref('StackOctet'), ".", app['SubnetOctetB'], ".0/24" ] ) }
    ])
  }

  availability_zones.each do |az|
    Resource("SubnetRouteTableAssociationPrivate#{az}") {
      Type 'AWS::EC2::SubnetRouteTableAssociation'
      Property('SubnetId', Ref("SubnetPrivate#{az}"))
      Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
    }
  end


  Resource("RedisSubnetGroup") {
    Type 'AWS::ElastiCache::SubnetGroup'
    Property('Description', 'Redis Subnet Group')
    Property('SubnetIds', [
      Ref('SubnetPrivateA'),
      Ref('SubnetPrivateB')
    ])
  }

  Resource("RedisReplicationGroup") {
    Type 'AWS::ElastiCache::ReplicationGroup'
    DependsOn ["RedisSubnetGroup"]
    Property('ReplicationGroupDescription', 'Redis Replication Group')
    Property('NumCacheClusters',FnIf('IsProduction', 2, 1))
    Property('Engine', 'redis')
    Property('CacheNodeType', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'CacheInstanceType'))
    Property('AutoMinorVersionUpgrade', true)
    Property('AutomaticFailoverEnabled', FnIf('IsProduction', true, false))
    Property('CacheSubnetGroupName', Ref('RedisSubnetGroup'))
    Property('EngineVersion', '2.8.19')
    Property('PreferredMaintenanceWindow', 'wed:05:45-wed:08:30')
    Property('SnapshotRetentionLimit', FnIf('IsProduction',14, Ref('AWS::NoValue')))
    Property('SnapshotWindow', FnIf('IsProduction','03:30-05:30',Ref('AWS::NoValue')))
    Property('SecurityGroupIds', [
      Ref('SecurityGroupCache')
    ])
  }

  Resource("RedisCacheDNS") {
    Type 'AWS::Route53::RecordSet'
    Property('HostedZoneName', FnJoin('', [ Ref('EnvironmentName'), '.', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix'), '.']))
    Property('Name', FnJoin('', ['redis.',Ref('EnvironmentName'), '.', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix'), '.']))
    Property('Type','CNAME')
    Property('TTL','60')
    Property('ResourceRecords',[ FnGetAtt('RedisReplicationGroup','PrimaryEndPoint.Address') ])
  }


}
