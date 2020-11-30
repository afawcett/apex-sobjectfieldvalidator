public with sharing class SObjectFieldValidator {

    private List<FieldValidation> validations;
    private FieldValidation current;

    public SObjectFieldValidator() {
        validations = new List<FieldValidation>();
    }

    public SObjectFieldValidator field(SObjectField field) {
        current = new FieldValidation();
        current.Field = field;
        validations.add(current);
        return this;
    }

    public SObjectFieldValidator withMessage(String message) {
        current.Message = message;
        return this;
    }

    public SObjectFieldValidator notNull() {
        current.Criteria.add(new NotNullCondition());
        return this;
    }

    public SObjectFieldValidator validate(SObject record) {
        for(FieldValidation validation : validations) {
            if(validation.validate(record.get(validation.Field))==false) {
                record.addError(validation.Field, validation.Message);
            }
        }
        return this;
    }

    public static SObjectFieldValidator build() {
        return new SObjectFieldValidator();
    }

    private class FieldValidation {
        public SObjectField Field;
        public String Message;
        public List<FieldValidationCondition> Criteria = new List<FieldValidationCondition>();
        public boolean validate(Object fieldValue) {
            for(FieldValidationCondition c : Criteria) {
                if(c.evaluate(fieldValue)==false) {
                    return false;
                }
            }
            return true;
        }
    }

    private abstract class FieldValidationCondition {
        abstract boolean evaluate(Object fieldValue);
    }    

    private class NotNullCondition extends FieldValidationCondition {
        override boolean evaluate(Object fieldValue) {
            return fieldValue!=null;
        }
    }
}
