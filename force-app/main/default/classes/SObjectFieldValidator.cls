/**
 * Proof of concept SObject Field Validator (Processor?) to explore the new addError runtime flexiblity
 */
public with sharing class SObjectFieldValidator {

    private FieldValidation current;
    private TriggerOperation triggerOperation;
    private List<FieldValidation> validations;

    private SObjectFieldValidator() {
        validations = new List<FieldValidation>();
    }

    public SObjectFieldValidator when(TriggerOperation triggerState) {
        triggerOperation = triggerState;
        return this;
    }

    public SObjectFieldValidator field(SObjectField field) {
        current = new FieldValidation();
        current.field = field;
        validations.add(current);
        if(triggerOperation!=null) {
            condition(new TriggerStateCondition(triggerOperation));
        }
        return this;
    }

    public SObjectFieldValidator when(SObjectField field) {
        FieldValidation whenFieldValidation = new FieldValidation();
        whenFieldValidation.field = field;
        current.whenFields.add(whenFieldValidation);
        return this;
    }

    public SObjectFieldValidator addError(String message) {
        current.message = message;
        return this;
    }

    public SObjectFieldValidator equals(Object value) {
        condition(new EqualsCondition(value));
        return this;
    }

    public SObjectFieldValidator hasChanged() {
        condition(new HasChangedCondition());
        return this;
    }

    public SObjectFieldValidator isNull() {
        condition(new IsNullCondition());
        return this;
    }

    public SObjectFieldValidator condition(FieldValidationCondition condition) {
        // Started adding related field crtierias?
        if(current.whenFields.size()==0) {
            // Criteria related to determine if the field validation is needed?
            if(condition instanceof FieldValidationPrecheck) {
                current.whenCriteria.add(condition);
            } else {
                // Criteria related to determining if the field is in error
                current.errorCriteria.add(condition);
            }
        } else {
            // Add this criteria to the last added related field to this validation
            current.whenFields[current.whenFields.size()-1].whenCriteria.add(condition);
        }            
        return this;
    }

    public SObjectFieldValidator validate(List<SObject> records) {
        return validate(null, new Map<Id, SObject>(), new Map<Id, SObject>(records));
    }

    public SObjectFieldValidator validate(TriggerOperation triggerState, Map<Id, SObject> oldMap, Map<Id, SObject> newMap) {
        return validate(triggerState, oldMap, newMap, null);
    }

    public SObjectFieldValidator validate(TriggerOperation triggerState, Map<Id, SObject> oldMap, Map<Id, SObject> newMap, Map<SObjectField, Map<Id, SObject>> relatedRecords) {
        // Stated used during validation
        FieldValidationContext ctx = new FieldValidationContext();
        ctx.triggerState = triggerState;
        ctx.relatedRecords = relatedRecords==null ? new Map<SObjectField, Map<Id, SObject>>() : relatedRecords;
        // Prescan field pre-validation critiera to determine fields to continue to process
        List<FieldValidation> fieldsRequiringValidation = new List<FieldValidation>();
        for(SObject newRecord : newMap.values()) {
            for(FieldValidation validation : validations) {
                // Does this require validation?
                ctx.record = newRecord;
                ctx.oldRecord = oldMap.get(newRecord.Id);
                ctx.fieldValue = ctx.record.get(validation.field);
                ctx.oldFieldValue = ctx.oldRecord?.get(validation.field);
                if(validation.requiresValidationPhase1(ctx)) {
                    fieldsRequiringValidation.add(validation);
                }            
            }
        }
        // Prequery related records?
        for(FieldValidation validation : fieldsRequiringValidation) {
            // Lookup field?
            DescribeFieldResult validationFieldDescribe = validation.field.getDescribe();
            if(validationFieldDescribe.getType() == DisplayType.Reference) {
                // Related records provided by caller?
                if(ctx.relatedRecords.containsKey(validation.field)) {
                    continue;
                }
                // TOOD: This prequerying could be further optimized by grouping validations over the same child object
                SObjectType referencedObjectType = validationFieldDescribe.getReferenceTo()[0];
                DescribeSObjectResult referencedObjectDescribe = referencedObjectType.getDescribe();
                Map<String, SObjectField> referencedObjectFields = referencedObjectDescribe.fields.getMap();
                List<String> relatedQueryFields = new List<String>();
                // 'when' field from the related object?
                for(FieldValidation whenFieldValidation : validation.whenFields) {
                    String relatedFieldName = whenFieldValidation.field.getDescribe().getLocalName();
                    if(referencedObjectFields.containsKey(relatedFieldName)) {
                        relatedQueryFields.add(relatedFieldName);
                    }
                }
                // Query related records with fields referenced by 'when' conditions
                if(relatedQueryFields.size()>0) {
                    String relatedQuery = 
                        'select ' + String.escapeSingleQuotes(String.join(relatedQueryFields, ',')) + 
                        ' from ' + String.escapeSingleQuotes(referencedObjectDescribe.getName()) + 
                        ' where Id in :ids';
                    Set<Id> ids = new Set<Id>();
                    for(SObject newRecord : newMap.values()) {
                        Id relatedId = (Id) newRecord.get(validation.field);
                        if(relatedId!=null) {
                            ids.add(relatedId);
                        }
                    }
                    ctx.relatedRecords.put(validation.field, new Map<Id, SObject>(Database.query(relatedQuery)));
                }
            }
        }
        // Perform field validations
        for(SObject newRecord : newMap.values()) {
            for(FieldValidation validation : fieldsRequiringValidation) {
                ctx.record = newRecord;
                ctx.oldRecord = oldMap.get(newRecord.Id);
                ctx.fieldValue = ctx.record.get(validation.field);
                ctx.oldFieldValue = ctx.oldRecord?.get(validation.field);
                if(validation.requiresValidationPhase2(ctx)) {
                    if(validation.hasErrors(ctx)) {
                        newRecord.addError(validation.Field, validation.Message);
                    }            
                }
            }    
        }

        return this;
    }

    public static SObjectFieldValidator build() {
        return new SObjectFieldValidator();
    }

    /**
     * Manages state during a given validation cycle
     */
    private class FieldValidationContext {
        SObject record;
        SObject oldRecord;
        Object fieldValue; 
        Object oldFieldValue;
        TriggerOperation triggerState;
        Map<SObjectField, Map<Id, SObject>> relatedRecords;
    }
    
    /**
     * Captured metadata for a given field validation (no stated related to validation themselves)
     */
    private class FieldValidation {

        public SObjectField field;
        public String message;
        public List<FieldValidation> whenFields = new List<FieldValidation>();
        public List<FieldValidationCondition> whenCriteria = new List<FieldValidationCondition>();
        public List<FieldValidationCondition> errorCriteria = new List<FieldValidationCondition>();

        /**
         * Called by the validator to check if the field needs validating at all (ctx does not contain any related field data, check this in phase 2)
         */
        public boolean requiresValidationPhase1(FieldValidationContext ctx) {
            // If any of the follow criteria fails the field does not need validating
            for(FieldValidationCondition criteria : whenCriteria) {
                if(criteria.evaluate(ctx)==false) {
                    return false;
                }
            }
            return true;
        }
        
        /**
         * Called by the validator to determine if any related fields (on the parent or related child records) indicate validation reqiured
         */
        public boolean requiresValidationPhase2(FieldValidationContext ctx) {
            // If any of the follow related field criteria fails the field does need validating
            if(whenFields.size()>0) {
                FieldValidationContext whenCtx = new FieldValidationContext();
                if(ctx.relatedRecords.containsKey(field)) {
                    Map<Id, SObject> relatedRecords = ctx.relatedRecords.get(field);
                    whenCtx.record = relatedRecords.get((Id) ctx.fieldValue);
                    whenCtx.oldRecord = null;
                } else {
                    whenCtx.record = ctx.record;
                    whenCtx.oldRecord = ctx.oldRecord;    
                }
                whenCtx.triggerState = ctx.triggerState;
                for(FieldValidation whenValidation : whenFields) {
                    whenCtx.fieldValue = whenCtx.record.get(whenValidation.field);
                    whenCtx.oldFieldValue = whenCtx.oldRecord==null ? null : whenCtx.oldRecord.get(whenValidation.field);    
                    for(FieldValidationCondition criteria : whenValidation.whenCriteria) {
                        if(criteria.evaluate(whenCtx)==false) {
                            return false;
                        }
                    }
                }    
            }
            return true;
        }
        
        public boolean hasErrors(FieldValidationContext ctx) {
            // Assume that if the caller called this it determined validation was needed
            if(errorCriteria.size()==0 && message!=null) {
                return true;
            }            
            // Evaluate crtiera on the field itself to determine if its in error
            for(FieldValidationCondition criteria : errorCriteria) {
                if(criteria.evaluate(ctx)) {
                    return true;
                }
            }
            return false;
        }
    }

    /**
     * Encapsulates a given validation for a field, ctx gives access to broader record, related records, old values etc
     */
    public abstract class FieldValidationCondition {
        abstract boolean evaluate(FieldValidationContext ctx);
    }    

    /**
     * Lets the validation logic know this is condition to evaluate to determine if the field needs validation
     */
    public interface FieldValidationPrecheck {}

    private class HasChangedCondition extends FieldValidationCondition implements FieldValidationPrecheck {
        override boolean evaluate(FieldValidationContext ctx) {
            return ctx.fieldValue == ctx.oldFieldValue ? false : true;
        }
    }

    /*** Various condition implementations invoked from the fluent methods above ***/

    private class TriggerStateCondition extends FieldValidationCondition implements FieldValidationPrecheck {
        private TriggerOperation triggerOperation;
        public TriggerStateCondition(TriggerOperation triggerState) { triggerOperation = triggerState; }
        override boolean evaluate(FieldValidationContext ctx) {
            return triggerOperation == ctx.triggerState;
        }
    }

    private class IsNullCondition extends FieldValidationCondition {
        override boolean evaluate(FieldValidationContext ctx) {
            return ctx.fieldValue==null;
        }
    }

    private class EqualsCondition extends FieldValidationCondition {
        Object equalValue;
        private EqualsCondition(Object value) { equalValue = value; }
        override boolean evaluate(FieldValidationContext ctx) {
            return ctx.fieldValue == equalValue;
        }
    }
}