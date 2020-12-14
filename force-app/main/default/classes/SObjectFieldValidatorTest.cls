@IsTest
private class SObjectFieldValidatorTest {

    private static final Id TEST_ACCOUNT_ID = Account.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
    private static final Id TEST_OPPORTUNIT_ID = Opportunity.SObjectType.getDescribe().getKeyPrefix()+'000000000001';

    private static SObjectFieldValidator buildTestValidator() {
        // Test validator used for these tests
        return SObjectFieldValidator.build()            
            .when(TriggerOperation.AFTER_UPDATE)
                .field(Opportunity.Description).hasChanged().isNull().addError('Description must be specified when Opportunity is closed')
                    .when(Opportunity.StageName).hasChanged().equals('Closed Won')
                .field(Opportunity.AccountId).hasChanged().addError('Account does not have any employees')
                    .when(Account.NumberOfEmployees).isNull();    
    }

    @IsTest
    private static void givenInMemoryNullProducesError() {
        // Given
        Id opportunityId = Opportunity.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
        Opportunity opp = new Opportunity(Id = opportunityId, Description = null, StageName = 'Closed Won');
        List<Opportunity> opps = new List<Opportunity>();
        opps.add(opp);
        // When
        SObjectFieldValidator.build()            
            .field(Opportunity.Description).isNull().addError('Description must be specified when Opportunity is closed')
                .when(Opportunity.StageName).equals('Closed Won')
            .validate(opps);
        // Then
        List<Database.Error> errors = opp.getErrors();
        System.assertEquals(1, errors.size());
        System.assertEquals('Description', errors[0].getFields()[0]);
        System.assertEquals('Description must be specified when Opportunity is closed', errors[0].getMessage());
    }

    @IsTest
    private static void givenInMemoryRelationshipValidationProducesError() {
        // Given
        Account relatedAccount = 
            new Account(Id = TEST_ACCOUNT_ID, Name = 'Test', NumberOfEmployees = null);
        Map<Id, SObject> oldMap = 
            new Map<Id, SObject> { TEST_OPPORTUNIT_ID => 
                new Opportunity(Id = TEST_OPPORTUNIT_ID, StageName = 'Prospecting', Description = 'X', AccountId = null)};
        Map<Id, SObject> newMap = 
            new Map<Id, SObject> { TEST_OPPORTUNIT_ID => 
                new Opportunity(Id = TEST_OPPORTUNIT_ID, StageName = 'Closed Won', Description = null, AccountId = TEST_ACCOUNT_ID)};
        Map<SObjectField, Map<Id, SObject>> relatedRecords = 
            new Map<SObjectField, Map<Id, SObject>> {
                Opportunity.AccountId => 
                    new Map<Id, SObject>(new List<Account> { relatedAccount })};
        // When
        buildTestValidator().validate(TriggerOperation.AFTER_UPDATE, oldMap, newMap, relatedRecords); 
        // Then
        List<Database.Error> errors = newMap.get(TEST_OPPORTUNIT_ID).getErrors();
        System.assertEquals(2, errors.size());
        System.assertEquals('AccountId', errors[0].getFields()[0]);
        System.assertEquals('Account does not have any employees', errors[0].getMessage());
        System.assertEquals('Description', errors[1].getFields()[0]);
        System.assertEquals('Description must be specified when Opportunity is closed', errors[1].getMessage());
    }

    @IsTest
    private static void givenhasChangedNullOrEqualsProducesErrors() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = null);        
        insert relatedAccount;
        Id opportunityId = Opportunity.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
        Id accountId = relatedAccount.Id;
        TriggerOperation triggerState = TriggerOperation.AFTER_UPDATE;
        Map<Id, SObject> oldMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Prospecting', Description = 'X', AccountId = null)};
        Map<Id, SObject> newMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Closed Won', Description = null, AccountId = accountId)};
        // When
        buildTestValidator().validate(triggerState, oldMap, newMap); 
        // Then
        List<Database.Error> errors = newMap.get(opportunityId).getErrors();
        System.assertEquals(2, errors.size());
        System.assertEquals('AccountId', errors[0].getFields()[0]);
        System.assertEquals('Account does not have any employees', errors[0].getMessage());
        System.assertEquals('Description', errors[1].getFields()[0]);
        System.assertEquals('Description must be specified when Opportunity is closed', errors[1].getMessage());
    }

    @IsTest
    private static void givenNoChangedNotNullProducesNoErrors() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = 100);        
        insert relatedAccount;
        Id opportunityId = Opportunity.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
        Id accountId = relatedAccount.Id;
        TriggerOperation triggerState = TriggerOperation.AFTER_UPDATE;
        Map<Id, SObject> oldMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Closed Won', Description = 'X', AccountId = null)};
        Map<Id, SObject> newMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Closed Won', Description = null, AccountId = accountId)};
        // When
        buildTestValidator().validate(triggerState, oldMap, newMap); 
        // Then
        List<Database.Error> errors = newMap.get(opportunityId).getErrors();
        System.assertEquals(0, errors.size());
    }

    @IsTest
    private static void givenChangedNotNullProducesNoErrors() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = 100);        
        insert relatedAccount;
        Id opportunityId = Opportunity.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
        Id accountId = relatedAccount.Id;
        TriggerOperation triggerState = TriggerOperation.AFTER_UPDATE;
        Map<Id, SObject> oldMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Prospecting', Description = 'X', AccountId = null)};
        Map<Id, SObject> newMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Closed Won', Description = 'Description', AccountId = accountId)};
        // When
        buildTestValidator().validate(triggerState, oldMap, newMap); 
        // Then
        List<Database.Error> errors = newMap.get(opportunityId).getErrors();
        System.assertEquals(0, errors.size());
    }

    @IsTest
    private static void givenNoChangedNotNullProducesNoErrorsNoSQL() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = 100);        
        insert relatedAccount;
        Id opportunityId = Opportunity.SObjectType.getDescribe().getKeyPrefix()+'000000000001';
        Id accountId = relatedAccount.Id;
        TriggerOperation triggerState = TriggerOperation.AFTER_UPDATE;
        Map<Id, SObject> oldMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Closed Won', Description = 'X', AccountId = accountId)};
        Map<Id, SObject> newMap = new Map<Id, SObject>{opportunityId => new Opportunity(Id = opportunityId, StageName = 'Closed Won', Description = null, AccountId = accountId)};
        // When
        buildTestValidator().validate(triggerState, oldMap, newMap); 
        // Then
        List<Database.Error> errors = newMap.get(opportunityId).getErrors();
        System.assertEquals(0, errors.size());
        System.assertEquals(0, Limits.getQueries());
    }
}
