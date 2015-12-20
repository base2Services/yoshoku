require 'cfndsl'

CloudFormation {

  # Template metadata
  AWSTemplateFormatVersion "2010-09-09"
  Description "#{application_name} - PostgreSQL v#{cf_version}"

  # AZ's
  AvailabilityZones = ['A', 'B']

  # Parameters
  Parameter("EnvironmentType"){ Type 'String' }
  Parameter("EnvironmentName"){ Type 'String' }
  #Parameter("RDSSnapshotID"){ Type 'String' }
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

  Condition('IsProduction', FnEquals(Ref('EnvironmentType'), 'production'))

  availability_zones.each do |az|
    Resource("SubnetPrivate#{az}") {
      Type 'AWS::EC2::Subnet'
      Property('VpcId', Ref('VPC'))
      Property('CidrBlock', FnJoin( "", [ FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".", postgresql["SubnetOctet#{az}"], ".0/24" ] ))
      Property('AvailabilityZone', FnSelect(azId[az], FnGetAZs(Ref( "AWS::Region" )) ))
      Property('Tags',[
        {
          Key: 'Name', Value: FnJoin( "", [ Ref('EnvironmentName'), "-postgresql-private#{az}"])
        }
      ])
    }
  end


  Resource("SecurityGroupPostgreSQL") {
    Type 'AWS::EC2::SecurityGroup'
    Property('VpcId', Ref('VPC'))
    Property('GroupDescription', 'PostgreSQL PostgreSQL Access')
    Property('SecurityGroupIngress', [
      { 'IpProtocol' => 'tcp', 'FromPort' => '5432', 'ToPort' => '5432', 'CidrIp' => FnJoin( "", [  FnFindInMap('EnvironmentType', Ref('EnvironmentType'),'NetworkPrefix'), ".", Ref('StackOctet'), ".0.0/16" ] ) },
    ])
  }

  AvailabilityZones.each do |az|
  Resource("SubnetRouteTableAssociationPrivate#{az}") {
    Type 'AWS::EC2::SubnetRouteTableAssociation'
    Property('SubnetId', Ref("SubnetPrivate#{az}"))
    Property('RouteTableId', Ref("RouteTablePrivate#{az}"))
  }
  end


  Resource("PostgreSQLSubnetGroup") {
    Type 'AWS::RDS::DBSubnetGroup'
    Property('DBSubnetGroupDescription','Private subnets for RDS Instance')
    Property('SubnetIds', [Ref('SubnetPrivateA'), Ref('SubnetPrivateB')])
  }

  Resource("PostgreSQLParameters") {
    Type 'AWS::RDS::DBParameterGroup'
    Property('Description','PostgreSQL RDS Parameters')
    Property('Family', 'postgres9.4')
  }


  Resource("PostgreSQL") {
    Type 'AWS::RDS::DBInstance'
    Property('DBInstanceClass', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'RDSInstanceType'))
    Property('AllocatedStorage','300')
    Property('StorageType', 'gp2')
    Property('Engine','postgres')
    Property('Engine','9.4.1')
    Property('MasterUsername', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'RDSMasterUsername'))
    Property('MasterUserPassword', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'RDSMasterPassword'))
    #Property('DBSnapshotIdentifier', FnIf('IsProduction','', Ref('RDSSnapshotID')))
    Property('DBSubnetGroupName', Ref('PostgreSQLSubnetGroup'))
    Property('VPCSecurityGroups',[ Ref('SecurityGroupPostgreSQL') ])
    Property('MultiAZ', FnIf('IsProduction', 'True', 'False'))
    Property('Tags',[
      {
        'Key' => 'Name',
        'Value' => FnJoin("",[ Ref('EnvironmentName'), '-PostgreSQL'])
      }
    ])
  }
  Resource("DatabaseIntHostRecord") {
    Type 'AWS::Route53::RecordSet'
    Property('HostedZoneName', FnJoin('', [ Ref('EnvironmentName'), '.', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix'), '.']))
    Property('Name', FnJoin('', [ 'db', '.', Ref('EnvironmentName'), '.', FnFindInMap('EnvironmentType',Ref('EnvironmentType'),'DnsDomainPrefix'), '.' ]))
    Property('Type','CNAME')
    Property('TTL','60')
    Property('ResourceRecords', [ FnGetAtt('PostgreSQL','Endpoint.Address') ])
  }

}
