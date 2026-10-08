import { post } from "./apiClient";

export const registerUser = (user) => post("/auth/register", user);
