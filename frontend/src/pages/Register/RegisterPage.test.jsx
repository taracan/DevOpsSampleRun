// RegisterPage.test.jsx: the register form, from typing to the next page.
// registerUser is replaced by a fake, so no backend is needed; the page
// runs inside an in-memory router with the real routes.

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import AppRoutes from "../../routes/AppRoutes";
import { registerUser } from "../../services/authService";

vi.mock("../../services/authService", () => ({ registerUser: vi.fn() }));

function renderAt(path) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <AppRoutes />
    </MemoryRouter>
  );
}

async function fillAndSubmit(user) {
  await user.type(screen.getByLabelText("Name"), "Alice");
  await user.type(screen.getByLabelText("Email"), "alice@example.com");
  await user.type(screen.getByLabelText("Password"), "secret123");
  await user.click(screen.getByRole("button", { name: "Register" }));
}

describe("RegisterPage", () => {
  beforeEach(() => {
    registerUser.mockReset();
  });

  it("marks the fields as required, with a 6-character minimum password", () => {
    renderAt("/register");

    expect(screen.getByLabelText("Name")).toBeRequired();
    expect(screen.getByLabelText("Email")).toHaveAttribute("type", "email");
    expect(screen.getByLabelText("Password")).toHaveAttribute("minLength", "6");
  });

  it("registers and shows the success page with the user's name", async () => {
    registerUser.mockResolvedValue({ id: 1, name: "Alice", email: "alice@example.com" });
    const user = userEvent.setup();
    renderAt("/register");

    await fillAndSubmit(user);

    expect(registerUser).toHaveBeenCalledWith({
      name: "Alice",
      email: "alice@example.com",
      password: "secret123",
    });
    expect(await screen.findByText("Registered successfully!")).toBeInTheDocument();
    expect(screen.getByText("Welcome, Alice.")).toBeInTheDocument();
  });

  it("shows the server's error and stays on the form", async () => {
    registerUser.mockRejectedValue(new Error("Email is already registered"));
    const user = userEvent.setup();
    renderAt("/register");

    await fillAndSubmit(user);

    expect(await screen.findByText("Email is already registered")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Register" })).toBeEnabled();
  });

  it("disables the button while the request is in flight", async () => {
    registerUser.mockReturnValue(new Promise(() => {})); // never settles
    const user = userEvent.setup();
    renderAt("/register");

    await fillAndSubmit(user);

    expect(screen.getByRole("button", { name: "Registering..." })).toBeDisabled();
  });

  it("redirects / to the register page", () => {
    renderAt("/");

    expect(screen.getByRole("heading", { name: /create your/i })).toBeInTheDocument();
  });
});
