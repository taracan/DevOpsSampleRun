import { useState } from "react";
import { useNavigate } from "react-router-dom";
import FormInput from "../../components/FormInput/FormInput";
import { registerUser } from "../../services/authService";
import { PATHS } from "../../routes/paths";

const INITIAL_FORM = { name: "", email: "", password: "" };

export default function RegisterPage() {
  const [form, setForm] = useState(INITIAL_FORM);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleChange = (e) => setForm({ ...form, [e.target.name]: e.target.value });

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const user = await registerUser(form);
      navigate(PATHS.SUCCESS, { state: { name: user.name } });
    } catch (err) {
      setError(err.message || "Could not reach the server");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="card">
      <h1>Create an account</h1>
      <form onSubmit={handleSubmit}>
        <FormInput label="Name" name="name" value={form.name} onChange={handleChange} required />
        <FormInput label="Email" name="email" type="email" value={form.email} onChange={handleChange} required />
        <FormInput label="Password" name="password" type="password" minLength={6} value={form.password} onChange={handleChange} required />
        <button type="submit" disabled={loading}>{loading ? "Registering..." : "Register"}</button>
      </form>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
