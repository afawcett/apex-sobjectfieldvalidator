public with sharing class SObjectFieldValidator {

    private List<FieldValidation> validations;
    private FieldValidation current;
    private TriggerOperation triggerOperation;

    public SObjectFieldValidator() {
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
        current.whenValidations.add(whenFieldValidation);
        return this;
    }

    public SObjectFieldValidator withMessage(String message) {
        current.message = message;
        return this;
    }

    public SObjectFieldValidator equals(Object value) {
        current.addCriteria(new EqualsCondition(value));
        return this;
    }

    public SObjectFieldValidator hasChanged() {
        current.addCriteria(new HasChangedCondition());
        return this;
    }

    public SObjectFieldValidator isNull() {
        current.addCriteria(new IsNullCondition());
        return this;
    }

    public SObjectFieldValidator validate(TriggerOperation triggerState, Map<Id, SObject> oldMap, Map<Id, SObject> newMap) {

        FieldValidationContext ctx = new FieldValidationContext();
        ctx.triggerState = null;
        ctx.relatedRecords = new Map<SObjectField, Map<Id, SObject>>();

        // Prequery related records for use by related field validations
        for(FieldValidation validation : validations) {
            DescribeFieldResult validationFieldDescribe = validation.field.getDescribe();
            // Lookup field?
            if(validationFieldDescribe.getType() == DisplayType.Reference) {
                // TOOD: Check 'hasChanged' condition to void doing this if the related record reference has not changed and hence the validation will not execute
                // TODO: Some of the following code could be done in the 'build' phase to improve performance incase of iterative calls to this method
                SObjectType referencedObjectType = validationFieldDescribe.getReferenceTo()[0];
                DescribeSObjectResult referencedObjectDescribe = referencedObjectType.getDescribe();
                Map<String, SObjectField> referencedObjectFields = referencedObjectDescribe.fields.getMap();
                List<String> relatedQueryFields = new List<String>();
                // 'when' field from the related object?
                for(FieldValidation whenFieldValidation : validation.whenValidations) {
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

        for(SObject newRecord : newMap.values()) {
            for(FieldValidation validation : validations) {
                ctx.record = newRecord;
                ctx.oldRecord = oldMap.get(newRecord.Id);
                ctx.fieldValue = ctx.record.get(validation.field);
                ctx.oldFieldValue = ctx.oldRecord.get(validation.field);
                if(validation.validate(ctx)==false) {
                    newRecord.addError(validation.Field, validation.Message);
                }
            }    
        }
        return this;
    }

    public SObjectFieldValidator validate(List<SObject> records) {
        return this;
    }

    @TestVisible
    private static void setMockQueryResult(SObjectField field, List<SObject> results)
    {    
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
        public List<FieldValidation> whenValidations = new List<FieldValidation>();
        public List<FieldValidationCondition> criteria = new List<FieldValidationCondition>();
        public void addCriteria(FieldValidationCondition condition) {
            if(whenValidations.size()==0) {
                criteria.add(condition);
            } else {
                whenValidations[whenValidations.size()-1].addCriteria(condition);
            }
        }
        public boolean validate(FieldValidationContext ctx) {
            if(whenValidations.size()>0) {
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
                for(FieldValidation whenValidation : whenValidations) {
                    whenCtx.fieldValue = whenCtx.record.get(whenValidation.field);
                    whenCtx.oldFieldValue = whenCtx.oldRecord==null ? null : ctx.oldRecord.get(whenValidation.field);    
                    if(whenValidation.validate(whenCtx)==false) {
                        return false;
                    }
                }    
            }
            for(FieldValidationCondition fieldValidationCondition : criteria) {
                if(fieldValidationCondition.evaluate(ctx)==false) {
                    return false;
                }
            }
            return true;
        }
    }

    private abstract class FieldValidationCondition {
        abstract boolean evaluate(FieldValidationContext ctx);
    }    

    private class HasChangedCondition extends FieldValidationCondition {
        override boolean evaluate(FieldValidationContext ctx) {
            return ctx.oldFieldValue == null ? true : !ctx.fieldValue.equals(ctx.oldFieldValue);
        }
    }

    private class TriggerStateCondition extends FieldValidationCondition {
        private TriggerOperation triggerOperation;
        public TriggerStateCondition(TriggerOperation triggerOperation) { this.triggerOperation = triggerOperation; }
        override boolean evaluate(FieldValidationContext ctx) {
            return ctx.triggerState==null ? false : this.triggerOperation.equals(ctx.triggerState);
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
            return ctx.fieldValue.equals(equalValue);
        }
    }
}
