/**
 * Very basic trigger handler framework, allows tests to inject different handlers to highlight hard coded vs dynamic validation approaches
 *
 * teste fernando de deploy
 */
trigger OpportunityTrigger on Opportunity (after update) {
    OpportunityTriggerHandler.execute(Trigger.operationType, Trigger.oldMap, Trigger.newMap);
}
