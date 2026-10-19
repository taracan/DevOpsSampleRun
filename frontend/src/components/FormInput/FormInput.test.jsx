// FormInput.test.jsx: the labelled input used by the register form.
// Checks the label is tied to the input and that extra props reach <input>.

import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import FormInput from "./FormInput";

describe("FormInput", () => {
  it("renders an input labelled by its label", () => {
    render(<FormInput label="Email" name="email" />);

    expect(screen.getByLabelText("Email")).toHaveAttribute("name", "email");
  });

  it("passes other props through to the input", () => {
    render(<FormInput label="Password" type="password" minLength={6} required />);

    const input = screen.getByLabelText("Password");
    expect(input).toHaveAttribute("type", "password");
    expect(input).toHaveAttribute("minLength", "6");
    expect(input).toBeRequired();
  });
});
