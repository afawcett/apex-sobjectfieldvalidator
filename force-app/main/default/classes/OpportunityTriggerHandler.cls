/**
 * Very basic trigger handler framework, allows tests to inject different handlers to highlight hard coded vs dynamic validation approaches
 */
public abstract class OpportunityTriggerHandler {
    public static OpportunityTriggerHandler current;
    public abstract void validate(TriggerOperation operation, Map<Id, Opportunity> oldMap, Map<Id, Opportunity> newMap);
    public static void execute(TriggerOperation operation, Map<Id, Opportunity> oldMap, Map<Id, Opportunity> newMap) {
        if(OpportunityTriggerHandler.current!=null) {
            current.validate(operation, oldMap, newMap); 
        }
    }
}
