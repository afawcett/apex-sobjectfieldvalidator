@IsTest
private class SObjectFieldValidatorTest {

    @IsTest
    private static void givenWhenThen() {
        // Given
        Opportunity op = new Opportunity();
        // When
        SObjectFieldValidator.build()            
            .field(Opportunity.Description).notEmpty().withMessage('Description must be specified when Opportunity is closed')
            //.field(Opportunity.Amount).greaterThan(1000).withMesage('Opportunity must be great than 100').when(Opportunity.Status).equals('CloseWon')
            //.field(Opportunity.AccountId).withIn(accountIds).withMessage('You can only associate special accounts').when(Opportunity.RecordTypeId).equals(specialOpRecordType)
            .validate(op);
        // Then
        List<Database.Error> errors = op.getErrors();
        System.assertEquals(1, op.getErrors().size());
        System.assertEquals('Description', errors[0].getFields()[0]);
        System.assertEquals('Description must be specified when Opportunity is closed', errors[0].getMessage());
    }
}
