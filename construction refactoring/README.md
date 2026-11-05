# Refactoring Plan Steps:

1. Move main construction logic from aljar to fabrica_construction
2. Refactoring fabrica_construction
    2.1. Enhance written code: apply DRY
    2.2. Seperation of Concern: base class [validator] service -> extends from it
3. Performance enhancement
    3.1. Database
        3.1.1. N+1 Problem
        3.1.2. Limit usage of get_doc, specially to retrieve fields
        3.1.3. Use indexes if need with repeated filters, join condition, or group by 
    3.2. Complexity time of Code
        3.2.1. Nested Loops
    3.3. Memory Lack
    3.4. Complexity Storage

---

- Method
    - Short Method -> Extract Method
        ```py
            # Before:
            def print_owing(invoice):
                print("***********************")
                print("**** Customer Owes ****")
                print("***********************")
                
                total = 0
                for order in invoice.orders:
                    total += order.amount
                    
                print(f"name: {invoice.customer}")
                print(f"amount: {total}")

            # after:
            def print_owing(invoice):
                print_banner()
                total = calculate_total(invoice.orders)
                print_details(invoice.customer, total)
        ```
    - Long Parameter List -> Introduce Parameter Object

- Mysterious Names -> Meaningful Naming
    - Variables
    - Methods
    - Classes

- Deep Nesting / Arrow Anti-pattern -> Guard Clauses
```py
# before:
def get_discount(user):
    if user is not None:
        if user.is_active:
            if user.has_membership:
                return 0.20
    return 0.0

# after (Guard Clauses):
def get_discount(user):
    if not user or not user.is_active:
        return 0.0
    if user.has_membership:
        return 0.20
    return 0.0
```

- Class
    - Replace Conditional with Polymorphism == Apply Open/Closed Principle
    - Extract Class

