require 'cfndsl'

CloudFormation do

  # Template metadata
  AWSTemplateFormatVersion '2010-09-09'
  Description "#{application_name} - Master v#{cf_version}"

    # Parameters
  Parameter("EnvironmentType"){
    Type 'String'
    AllowedValues ['production','dev']
    Default 'dev'
  }
  Parameter("EnvironmentName"){ Type 'String' }

  Parameter("ActiveMQEnabled"){
    Type 'String'
    AllowedValues ['true','false']
    Default 'true'
  }

  Parameter("RDSSnapshotID"){
    Type 'String'
    Default ''
  }

  Parameter("StackOctet") {
    Type 'String'
    Default '222'
  }

  Parameter("CertName") {
    Type 'String'
    Default 'STAR_aws_acmesystems_com.Sep.2020'
  }

  availability_zones.each do |az|
  Parameter("Nat#{az}EIPAllocationId") {
    Description 'Enter the eip allocation id or use dynamic to generate EIP as part of the stack'
    Type 'String'
    Default 'dynamic'
  }
  end

  Condition('ActiveMQEnabled', FnEquals(Ref('ActiveMQEnabled'), 'true'))

  vpc_params = {
    EnvironmentType: Ref('EnvironmentType'),
    EnvironmentName: Ref('EnvironmentName'),
    StackOctet: Ref('StackOctet')
  }
  availability_zones.each do |az|
    vpc_params.merge!("Nat#{az}EIPAllocationId" => Ref("Nat#{az}EIPAllocationId"))
  end
  Resource("VPCStack") {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://s3-#{source_region}.amazonaws.com/#{source_bucket}/cloudformation/#{cf_version}/vpc.json" )
    Property('TimeoutInMinutes', 5)
    Property('Parameters', vpc_params )
  }

  Resource("ElasticCacheStack") {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://s3-#{source_region}.amazonaws.com/#{source_bucket}/cloudformation/#{cf_version}/cache.json" )
    Property('TimeoutInMinutes', 5)
    Property('Parameters',{
      EnvironmentType: Ref('EnvironmentType'),
      EnvironmentName: Ref('EnvironmentName'),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      StackOctet: FnGetAtt('VPCStack', 'Outputs.StackOctet'),
      RouteTablePrivateA: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateA'),
      RouteTablePrivateB: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateB'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
    })
  }

  Resource("PostgreSQLStack") {
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://s3-#{source_region}.amazonaws.com/#{source_bucket}/cloudformation/#{cf_version}/postgresql_rdb.json" )
    Property('TimeoutInMinutes', 5)
    Property('Parameters',{
      EnvironmentType: Ref('EnvironmentType'),
      EnvironmentName: Ref('EnvironmentName'),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      StackOctet: FnGetAtt('VPCStack', 'Outputs.StackOctet'),
      RouteTablePrivateA: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateA'),
      RouteTablePrivateB: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateB'),
      SubnetPublicA: FnGetAtt('VPCStack', 'Outputs.SubnetPublicA'),
      SubnetPublicB: FnGetAtt('VPCStack', 'Outputs.SubnetPublicB'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
      SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
      SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev')
    })
  }

  Resource("WebAppStack") {
    Type 'AWS::CloudFormation::Stack'
    DependsOn(['PostgreSQLStack','ElasticCacheStack'])
    Property('TemplateURL', "https://s3-#{source_region}.amazonaws.com/#{source_bucket}/cloudformation/#{cf_version}/app.json" )
    Property('TimeoutInMinutes', 5)
    Property('Parameters',{
      EnvironmentType: Ref('EnvironmentType'),
      EnvironmentName: Ref('EnvironmentName'),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      CertName: Ref('CertName'),
      StackOctet: FnGetAtt('VPCStack', 'Outputs.StackOctet'),
      RouteTablePrivateA: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateA'),
      RouteTablePrivateB: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateB'),
      SubnetPublicA: FnGetAtt('VPCStack', 'Outputs.SubnetPublicA'),
      SubnetPublicB: FnGetAtt('VPCStack', 'Outputs.SubnetPublicB'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
      SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
      SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev')
    })
  }

  Resource("ActiveMQStack") {
    Type 'AWS::CloudFormation::Stack'
    DependsOn(['PostgreSQLStack'])
    Condition('ActiveMQEnabled')
    Property('TemplateURL', "https://s3-#{source_region}.amazonaws.com/#{source_bucket}/cloudformation/#{cf_version}/activemq.json" )
    Property('TimeoutInMinutes', 5)
    Property('Parameters',{
      EnvironmentType: Ref('EnvironmentType'),
      EnvironmentName: Ref('EnvironmentName'),
      VPC: FnGetAtt('VPCStack', 'Outputs.VPCId'),
      StackOctet: FnGetAtt('VPCStack', 'Outputs.StackOctet'),
      RouteTablePrivateA: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateA'),
      RouteTablePrivateB: FnGetAtt('VPCStack', 'Outputs.RouteTablePrivateB'),
      SubnetPublicA: FnGetAtt('VPCStack', 'Outputs.SubnetPublicA'),
      SubnetPublicB: FnGetAtt('VPCStack', 'Outputs.SubnetPublicB'),
      SecurityGroupBackplane: FnGetAtt('VPCStack', 'Outputs.SecurityGroupBackplane'),
      SecurityGroupOps: FnGetAtt('VPCStack', 'Outputs.SecurityGroupOps'),
      SecurityGroupDev: FnGetAtt('VPCStack', 'Outputs.SecurityGroupDev')
    })
  }

end
