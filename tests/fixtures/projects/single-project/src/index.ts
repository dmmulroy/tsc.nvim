// Test TypeScript file with intentional errors for testing

interface User {
  id: number;
  name: string;
  email: string;
}

// Type error: string assigned to number
const userId: number = "123";

// Property error: accessing non-existent property
function getUser(): User {
  const user = {
    id: 1,
    name: "John Doe",
    email: "john@example.com"
  };
  
  // This will cause an error
  return user.nonExistentProperty;
}

// Reference error: using undefined variable
function processUser() {
  return someUndefinedVariable;
}

export { User, getUser, processUser };