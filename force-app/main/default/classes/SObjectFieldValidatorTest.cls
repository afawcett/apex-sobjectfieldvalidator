@IsTest
private class SObjectFieldValidatorTest {

    @IsTest
    private static void givenWhenThen() {
        // Given
        Id opportunityId = Opportunity.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
        Id accountId = Account.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
        Map<Id, SObject> oldMap = new Map<Id, SObject>{opportunityId => new Opportunity(StageName = 'Closed Won', AccountId = null)};
        Map<Id, SObject> newMap = new Map<Id, SObject>{opportunityId => new Opportunity(StageName = 'Closed Won', AccountId = accountId)};
        TriggerOperation triggerState = TriggerOperation.AFTER_UPDATE;
        SObjectFieldValidator.setMockQueryResult(Opportunity.AccountId, new List<Account> { new Account(Id = accountId, NumberOfEmployees = null)});
        // When
        SObjectFieldValidator.build()            
            .when(TriggerOperation.AFTER_UPDATE)
                .field(Opportunity.Description).isNull().withMessage('Description must be specified when Opportunity is closed').when(Opportunity.StageName).equals('Close Won')
                .field(Opportunity.AccountId).field(Account.NumberOfEmployees).isNull().withMessage('Account does not have any employees')
            .validate(triggerState, oldMap, newMap);
        // Then
        List<Database.Error> errors = newMap.get(opportunityId).getErrors();
        System.assertEquals(1, errors.size());
        System.assertEquals('Description', errors[0].getFields()[0]);
        System.assertEquals('Description must be specified when Opportunity is closed', errors[0].getMessage());
        System.assertEquals('NumberOfEmployees', errors[1].getFields()[0]);
        System.assertEquals('Account does not have any employees', errors[1].getMessage());
    }
}
