export interface StepperRowProps {
  label?: string;
  value?: number;
  unit?: string;
  step?: number;
  min?: number;
  max?: number;
  style?: React.CSSProperties;
}
export declare function StepperRow(props: StepperRowProps): JSX.Element;
