/**
 * Test class is just used to illustrate with and without the use of SObjectFieldValidator 
 */
@IsTest
private class OpportunityTriggerTest {
    
    /**
     * Demonstrates the use of SObjectFieldValidator
     */
    public class WithSObjectFieldValidator extends OpportunityTriggerHandler {

        public override void validate(TriggerOperation operation, Map<Id, Opportunity> oldMap, Map<Id, Opportunity> newMap) {
            // Fluent style validation
            SObjectFieldValidator.build()            
                .when(TriggerOperation.AFTER_UPDATE)
                    .field(Opportunity.Description).whenChanged().isNull().addError('Description must be specified when Opportunity is closed')
                        .when(Opportunity.StageName).whenChanged().equals('Closed Won')
                    .field(Opportunity.AccountId).whenChanged().addError('Account does not have any employees')
                        .when(Account.NumberOfEmployees).isNull()
                .validate(operation, oldMap, newMap);
        }
    }

    /**
     * Illustrates equivalent code reqired when SObjectFieldValidator is not used (per example above)
     */
    public class WithHandCodedValidation extends OpportunityTriggerHandler {

        public override void validate(TriggerOperation operation, Map<Id, Opportunity> oldMap, Map<Id, Opportunity> newMap) {
            // Classic style validation
            switch on Trigger.operationType {
                when AFTER_UPDATE {
                    // Prescan to bulkify querying for related Accounts
                    Set<Id> accountIds = new Set<Id>();
                    for (Opportunity opp : newMap.values()) {
                        Opportunity oldOpp = oldMap.get(opp.Id);
                        if(opp.AccountId != oldOpp.AccountId) { // AccountId changed?
                            accountIds.add(opp.AccountId);
                        }
                    }                
                    // Query related Account records?
                    Map<Id, Account> associatedAccountsById = accountIds.size()==0 ? 
                        new Map<Id, Account>() : 
                        new Map<Id, Account>([select Id, NumberOfEmployees from Account where Id = :accountIds]);
                    // Validate
                    for (Opportunity opp : newMap.values()) {
                        Opportunity oldOpp = oldMap.get(opp.Id);
                        if(opp.StageName != oldOpp.StageName) { // Stage changed?
                            if(opp.StageName == 'Closed Won') { // Stage closed won?
                                if(opp.Description != oldOpp.Description) { // Description changed?               
                                    if(opp.Description == null) { // Description null?
                                        opp.Description.addError('Description must be specified when Opportunity is closed');
                                    }
                                }
                            }                                
                        }
                        if(opp.AccountId != oldOpp.AccountId) { // AccountId changed?
                            Account acct = associatedAccountsById.get(opp.AccountId);
                            if(acct!=null) { // Account queried?
                                if(acct.NumberOfEmployees==null) { // NumberOfEmployees null?
                                    opp.AccountId.addError('Account does not have any employees');
                                }    
                            }
                        }
                    }
                }
            }               
        }
    }

    @IsTest
    private static void withSObjectFieldValidatorThenRunTests() {
        // Given
        OpportunityTriggerHandler.current = new WithSObjectFieldValidator();
        // Then
        givenWhenChangedNullOrEqualsProducesErrors();
        givenNoChangedNotNullProducesNoErrors();
        givenChangedNotNullProducesNoErrors();
        givenNoChangedNotNullProducesNoErrorsNoSQL();
    }

    @IsTest
    private static void withHandedCodeValidationThenRunTests() {
        // Given
        OpportunityTriggerHandler.current = new WithHandCodedValidation();
        // Then
        givenWhenChangedNullOrEqualsProducesErrors();
        givenNoChangedNotNullProducesNoErrors();
        givenChangedNotNullProducesNoErrors();
        givenNoChangedNotNullProducesNoErrorsNoSQL();
    }

    private static void givenWhenChangedNullOrEqualsProducesErrors() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = null);        
        insert relatedAccount;
        Opportunity opp = new Opportunity(Name = 'Test', CloseDate = Date.today(), StageName = 'Prospecting', Description = 'X', AccountId = null);
        insert opp;
        opp.StageName = 'Closed Won';
        opp.Description = null;
        opp.AccountId = relatedAccount.Id;
        // When
        Database.SaveResult saveResult = Database.update(opp, false);
        // Then
        List<Database.Error> errors = saveResult.getErrors();
        System.assertEquals(2, errors.size());
        System.assertEquals('Description', errors[0].getFields()[0]);
        System.assertEquals('Description must be specified when Opportunity is closed', errors[0].getMessage());
        System.assertEquals('AccountId', errors[1].getFields()[0]);
        System.assertEquals('Account does not have any employees', errors[1].getMessage());
    }

    private static void givenNoChangedNotNullProducesNoErrors() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = 100);        
        insert relatedAccount;
        Opportunity opp = new Opportunity(Name = 'Test', CloseDate = Date.today(), StageName = 'Closed Won', Description = 'X', AccountId = null);
        insert opp;
        opp.StageName = 'Closed Won';
        opp.Description = null;
        opp.AccountId = relatedAccount.Id;
        // When
        Database.SaveResult saveResult = Database.update(opp, false);
        // Then
        List<Database.Error> errors = saveResult.getErrors();
        System.assertEquals(0, errors.size());
    }

    private static void givenChangedNotNullProducesNoErrors() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = 100);        
        insert relatedAccount;
        Opportunity opp = new Opportunity(Name = 'Test', CloseDate = Date.today(), StageName = 'Prospecting', Description = 'X', AccountId = null);
        insert opp;
        opp.StageName = 'Closed Won';
        opp.Description = 'Description';
        opp.AccountId = relatedAccount.Id;
        // When
        Database.SaveResult saveResult = Database.update(opp, false);
        // Then
        System.assertEquals(0, saveResult.getErrors().size());
    }

    private static void givenNoChangedNotNullProducesNoErrorsNoSQL() {
        // Given
        Account relatedAccount = new Account(Name = 'Test', NumberOfEmployees = 100);        
        insert relatedAccount;
        Opportunity opp = new Opportunity(Name = 'Test', CloseDate = Date.today(), StageName = 'Closed Won', Description = 'X', AccountId = relatedAccount.Id);
        insert opp;
        opp.StageName = 'Closed Won';
        opp.Description = null;
        opp.AccountId = relatedAccount.Id;
        // When
        Database.SaveResult saveResult = Database.update(opp, false);
        // Then
        List<Database.Error> errors = saveResult.getErrors();
        System.assertEquals(0, errors.size());
    }
}