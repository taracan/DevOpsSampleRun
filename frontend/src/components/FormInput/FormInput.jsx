import "./FormInput.css";

export default function FormInput({ label, ...props }) {
  return (
    <label className="form-input">
      <span>{label}</span>
      <input {...props} />
    </label>
  );
}
