public with sharing class SObjectFieldValidator {

    private FieldValidation current;
    private TriggerOperation triggerOperation;
    private List<FieldValidation> validations;

    private SObjectFieldValidator() {
        validations = new List<FieldValidation>();
    }

    public SObjectFieldValidator field(SObjectField field) {
        current = new FieldValidation();
        current.field = field;
        if(triggerOperation!=null) {
            current.addCriteria(new TriggerStateCondition(triggerOperation));
        }
        validations.add(current);
        return this;
    }

    public SObjectFieldValidator when(TriggerOperation triggerState) {
        triggerOperation = triggerState;
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
        current.addCriteria(new EqualsCondition(value));
        return this;
    }

    public SObjectFieldValidator whenChanged() {
        current.addCriteria(new HasChangedCondition());
        return this;
    }

    public SObjectFieldValidator isNull() {
        current.addCriteria(new IsNullCondition());
        return this;
    }

    public SObjectFieldValidator validate(List<SObject> records) {
        return validate(null, new Map<Id, SObject>(), new Map<Id, SObject>(records));
    }

    public SObjectFieldValidator validate(TriggerOperation triggerState, Map<Id, SObject> oldMap, Map<Id, SObject> newMap) {

        // Stated used during validation
        FieldValidationContext ctx = new FieldValidationContext();
        ctx.triggerState = triggerState;
        ctx.relatedRecords = new Map<SObjectField, Map<Id, SObject>>();

        // Prequery related records for use by related field validations
        for(FieldValidation validation : validations) {
            DescribeFieldResult validationFieldDescribe = validation.field.getDescribe();
            // Lookup field?
            if(validationFieldDescribe.getType() == DisplayType.Reference) {
                // TOOD: Split the logic in the 'hasErrors' method to prepass to enable only prequery of fields that need validation
                // TODO: Some of the following code could be done in the 'build' phase to improve performance incase of iterative calls to this method
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
                        'select ' + String.join(relatedQueryFields, ',') + 
                        ' from ' + referencedObjectDescribe.getName() + 
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
            for(FieldValidation validation : validations) {
                ctx.record = newRecord;
                ctx.oldRecord = oldMap.get(newRecord.Id);
                ctx.fieldValue = ctx.record.get(validation.field);
                ctx.oldFieldValue = ctx.oldRecord.get(validation.field);
                if(validation.hasErrors(ctx)) {
                    newRecord.addError(validation.Field, validation.Message);
                }    
            }    
        }

        return this;
    }

    public static SObjectFieldValidator build() {
        return new SObjectFieldValidator();
    }

    private class FieldValidationContext {
        SObject record;
        SObject oldRecord;
        Object fieldValue; 
        Object oldFieldValue;
        TriggerOperation triggerState;
        Map<SObjectField, Map<Id, SObject>> relatedRecords;
    }
    
    private class FieldValidation {

        public SObjectField field;
        public String message;
        public List<FieldValidation> whenFields = new List<FieldValidation>();
        public List<FieldValidationCondition> whenCriteria = new List<FieldValidationCondition>();
        public List<FieldValidationCondition> errorCriteria = new List<FieldValidationCondition>();

        public void addCriteria(FieldValidationCondition condition) {
            // Started adding related field crtierias?
            if(whenFields.size()==0) {
                // Criteria related to determine if the field validation is needed?
                if(condition instanceof FieldValidationPrecheck) {
                    whenCriteria.add(condition);
                } else {
                    // Criteria related to determining if the field is in error
                    errorCriteria.add(condition);
                }
            } else {
                // Add this criteria to the last added related field to this validation
                whenFields[whenFields.size()-1].whenCriteria.add(condition);
            }
        }

        public boolean hasErrors(FieldValidationContext ctx) {

            // If any of the follow criteria fails the field does not need validating
            for(FieldValidationCondition criteria : whenCriteria) {
                if(criteria.evaluate(ctx)==false) {
                    return false;
                }
            }
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
                // If there is no further error criteria then its assumed the related field criteria is the error criteria
                if(errorCriteria.size()==0) {
                    return true;
                }
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

    private abstract class FieldValidationCondition {
        abstract boolean evaluate(FieldValidationContext ctx);
    }    

    private interface FieldValidationPrecheck {}

    private class HasChangedCondition extends FieldValidationCondition implements FieldValidationPrecheck {
        override boolean evaluate(FieldValidationContext ctx) {
            return ctx.fieldValue == ctx.oldFieldValue ? false : true;
        }
    }

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

    @TestVisible
    private static void setMockQueryResult(SObjectField field, List<SObject> results) { }
}
