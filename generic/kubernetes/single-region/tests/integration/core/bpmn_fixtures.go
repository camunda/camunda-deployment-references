package core

import "fmt"

// basicProcessBPMN returns a minimal BPMN with start -> end. Used to validate
// the deployment endpoint without exercising any worker.
func basicProcessBPMN(processID string) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL"
                  id="Definitions_1"
                  targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:process id="%s" name="Integration Test" isExecutable="true">
    <bpmn:startEvent id="start">
      <bpmn:outgoing>toEnd</bpmn:outgoing>
    </bpmn:startEvent>
    <bpmn:endEvent id="end">
      <bpmn:incoming>toEnd</bpmn:incoming>
    </bpmn:endEvent>
    <bpmn:sequenceFlow id="toEnd" sourceRef="start" targetRef="end"/>
  </bpmn:process>
</bpmn:definitions>`, processID)
}

// inboundConnectorBPMN returns a BPMN that declares an HTTP-webhook inbound
// connector start event. The engine validates the connector type at deploy
// time, so this exercises the deployment validation path covered by the
// venom "TEST - Deploy Inbound Connector Process" step.
func inboundConnectorBPMN(processID string) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL"
                  xmlns:zeebe="http://camunda.org/schema/zeebe/1.0"
                  id="Definitions_inbound"
                  targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:process id="%s" name="Integration Test Inbound Connector" isExecutable="true">
    <bpmn:startEvent id="webhook-start" name="webhook">
      <bpmn:extensionElements>
        <zeebe:properties>
          <zeebe:property name="inbound.type" value="io.camunda:webhook:1" />
          <zeebe:property name="inbound.method" value="POST" />
          <zeebe:property name="inbound.context" value="integration-test-webhook" />
          <zeebe:property name="inbound.shouldValidateHmac" value="disabled" />
        </zeebe:properties>
      </bpmn:extensionElements>
      <bpmn:outgoing>toEnd</bpmn:outgoing>
    </bpmn:startEvent>
    <bpmn:endEvent id="end">
      <bpmn:incoming>toEnd</bpmn:incoming>
    </bpmn:endEvent>
    <bpmn:sequenceFlow id="toEnd" sourceRef="webhook-start" targetRef="end"/>
  </bpmn:process>
</bpmn:definitions>`, processID)
}
